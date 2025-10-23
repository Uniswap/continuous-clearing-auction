import {
  AssertionInterfaceType,
  BalanceAssertion,
  AuctionAssertion,
  EventAssertion,
  TotalSupplyAssertion,
  Assertion,
  Address,
  VariableAmount,
  InternalCheckpointStruct,
} from "../schemas/TestInteractionSchema";
import { Contract } from "ethers";
import { TokenContract } from "./types";
import { AuctionDeployer } from "./AuctionDeployer";
import { ZERO_ADDRESS, LOG_PREFIXES, ERROR_MESSAGES, TYPES, ONE_MILLION } from "./constants";
import { CheckpointStruct } from "../../../typechain-types/out/Auction";
import { resolveTokenAddress } from "./utils";
import hre from "hardhat";

// NOTE: Different from interface defined in the schema as it uses bigint, and no variance, since this comes directly from the contract
export interface AuctionState {
  isGraduated: boolean;
  clearingPrice: bigint;
  currencyRaised: bigint;
  latestCheckpoint: CheckpointStruct;
  currentBlock: number;
}

export interface BidderState {
  address: Address;
  tokenBalance: string;
  currencyBalance: string;
}

export class AssertionEngine {
  private auction: Contract;
  private token: TokenContract | null; // Contract or Native currency
  private currency: TokenContract | null; // Contract or Native currency
  private auctionDeployer: AuctionDeployer;

  constructor(
    auction: Contract,
    token: TokenContract | null,
    currency: TokenContract | null,
    auctionDeployer: AuctionDeployer,
  ) {
    this.auction = auction;
    this.token = token;
    this.currency = currency;
    this.auctionDeployer = auctionDeployer;
  }

  /**
   * Validates a single assertion by routing to the appropriate validation method.
   * @param assertion - The assertion to validate
   * @throws Error if the assertion fails validation
   */
  async validateAssertion(assertion: Assertion): Promise<void> {
    if (assertion.type === AssertionInterfaceType.BALANCE) {
      await this.validateBalanceAssertion(assertion);
    } else if (assertion.type === AssertionInterfaceType.TOTAL_SUPPLY) {
      await this.validateTotalSupplyAssertions([assertion]);
    } else if (assertion.type === AssertionInterfaceType.EVENT) {
      await this.validateEventAssertions([assertion]);
    } else if (assertion.type === AssertionInterfaceType.AUCTION) {
      await this.validateAuctionAssertions([assertion]);
    } else {
      throw new Error(ERROR_MESSAGES.INVALID_ASSERTION_TYPE);
    }
  }

  /**
   * Check if the actual value is within the specified variance of the expected value.
   * Supports three formats:
   * - Percentage: "5%" -> 5% tolerance
   * - Ratio: "0.05" -> 5% tolerance (decimal < 1)
   * - Raw amount: "100000000000000000" -> +/- exact amount tolerance
   * @param actual - The actual value
   * @param expected - The expected value
   * @param varianceStr - The variance string (percentage, ratio, or raw amount)
   * @returns True if actual is within variance bounds, false otherwise
   */
  private isWithinVariance(actual: bigint, expected: bigint, varianceStr: string): boolean {
    if (!varianceStr) {
      return actual === expected;
    }

    let varianceAmount: bigint;

    if (varianceStr.endsWith("%")) {
      // Percentage: convert to ratio and apply to expected (e.g., "5%" -> 5% of expected)
      const percentage = parseFloat(varianceStr.slice(0, -1));
      const ratio = percentage / 100;
      varianceAmount = (expected * BigInt(Math.floor(ratio * ONE_MILLION))) / BigInt(ONE_MILLION);
    } else {
      if (varianceStr.includes(".")) {
        const numericValue = parseFloat(varianceStr);
        // Ratio: treat as percentage in decimal form (e.g., "0.05" -> 5% of expected)
        varianceAmount = (expected * BigInt(Math.floor(numericValue * ONE_MILLION))) / BigInt(ONE_MILLION);
      } else {
        // Raw amount: use as absolute tolerance (e.g., "100000000000000000")
        varianceAmount = BigInt(varianceStr);
      }
    }

    const lowerBound = expected - varianceAmount;
    const upperBound = expected + varianceAmount;

    return actual >= lowerBound && actual <= upperBound;
  }

  /**
   * Validates equality between expected and actual values, supporting VariableAmount structures.
   * @param expected - Expected value (can be primitive or VariableAmount object)
   * @param actual - Actual value from the contract
   * @returns True if values are equal or within variance bounds
   * @throws Error if expected is an invalid object structure
   */
  private validateEquality(expected: any, actual: any): boolean {
    if (expected && typeof expected === TYPES.OBJECT) {
      let keys = Object.keys(expected);
      if (keys.length !== 2 || !keys.includes("amount") || !keys.includes("variation")) {
        throw new Error(ERROR_MESSAGES.CANNOT_VALIDATE_EQUALITY);
      }
      let expectedStruct = expected as VariableAmount;
      if (!this.isWithinVariance(actual, BigInt(expectedStruct.amount), expectedStruct.variation)) {
        return false;
      } else {
        return true;
      }
    } else {
      return expected.toString() === actual.toString();
    }
  }

  /**
   * Validates a balance assertion for a specific address and token.
   * @param assertion - Balance assertion containing address, token, expected balance, and optional variance
   * @throws Error if balance assertion fails or token is not found
   */
  async validateBalanceAssertion(assertion: BalanceAssertion): Promise<void> {
    const { address, token, expected, variance } = assertion;

    let actualBalance: bigint;
    const expectedBalance = BigInt(expected);

    const resolvedTokenAddress = await resolveTokenAddress(token, this.auctionDeployer);

    if (resolvedTokenAddress === ZERO_ADDRESS) {
      // Native currency
      actualBalance = await hre.ethers.provider.getBalance(address);
    } else {
      // ERC20 token
      const tokenContract = await hre.ethers.getContractAt("IERC20Minimal", resolvedTokenAddress);
      actualBalance = await tokenContract.balanceOf(address);
    }
    if (!this.isWithinVariance(actualBalance, expectedBalance, variance || "0")) {
      throw new Error(
        ERROR_MESSAGES.BALANCE_ASSERTION_FAILED(
          address,
          token,
          expectedBalance.toString(),
          actualBalance.toString(),
          variance,
        ),
      );
    }
    // Log actual balance for visibility
    const tokenSymbol = resolvedTokenAddress === ZERO_ADDRESS ? "ETH" : "tokens";
    console.log(
      LOG_PREFIXES.SUCCESS,
      `Assertion validated (within variance of ${variance}). Actual balance: ${actualBalance.toString()} ${tokenSymbol}`,
    );
  }

  /**
   * Validates total supply assertions for multiple tokens.
   * @param totalSupplyAssertion - Array of total supply assertions to validate
   * @throws Error if any total supply assertion fails or token is not found
   */
  async validateTotalSupplyAssertions(totalSupplyAssertion: TotalSupplyAssertion[]): Promise<void> {
    for (const assertion of totalSupplyAssertion) {
      const tokenAddress = await resolveTokenAddress(assertion.token, this.auctionDeployer);
      const token = await this.auctionDeployer.getTokenByAddress(tokenAddress);

      if (!token) {
        throw new Error(ERROR_MESSAGES.TOKEN_NOT_FOUND_BY_ADDRESS(tokenAddress));
      }
      const _addr = await token.getAddress();
      console.log(LOG_PREFIXES.INFO, "Token address for totalSupply():", _addr);
      const actualSupply = await token.totalSupply();
      const expectedSupply = BigInt(assertion.expected);

      if (actualSupply !== expectedSupply) {
        throw new Error(
          ERROR_MESSAGES.TOTAL_SUPPLY_ASSERTION_FAILED(expectedSupply.toString(), actualSupply.toString()),
        );
      }

      console.log(
        LOG_PREFIXES.ASSERTION,
        "Total supply check:",
        tokenAddress,
        "has",
        actualSupply.toString(),
        "total supply, expected",
        expectedSupply.toString(),
      );
    }
  }

  /**
   * Validates auction state assertions including main auction fields and checkpoint data.
   * @param auctionAssertions - Array of auction assertions, optionally including variances, to validate
   * @throws Error if any auction assertion fails
   */
  async validateAuctionAssertions(auctionAssertions: AuctionAssertion[]): Promise<void> {
    for (const assertion of auctionAssertions) {
      console.log(LOG_PREFIXES.INFO, "Auction assertion validation");
      // Get the current auction state
      const auctionState = await this.getAuctionState();
      this.validateAuctionAssertion(assertion, auctionState);
      const { type, ...assertionWithoutType } = assertion;
      console.log(
        LOG_PREFIXES.SUCCESS,
        "Auction state check successful. Expected",
        assertionWithoutType,
        "got",
        auctionState,
      );
    }
  }

  async validateAuctionAssertion(auctionAssertion: AuctionAssertion, auctionState: AuctionState): Promise<void> {
    if (auctionAssertion.isGraduated !== undefined) {
      if (!this.validateEquality(auctionAssertion.isGraduated, auctionState.isGraduated)) {
        this.throwAuctionAssertionError(
          auctionAssertion.isGraduated,
          auctionState.isGraduated,
          "isGraduated",
          ERROR_MESSAGES.AUCTION_ASSERTION_FAILED,
        );
      }
    }
    if (auctionAssertion.clearingPrice !== undefined) {
      if (!this.validateEquality(auctionAssertion.clearingPrice, auctionState.clearingPrice)) {
        this.throwAuctionAssertionError(
          auctionAssertion.clearingPrice,
          auctionState.clearingPrice,
          "clearingPrice",
          ERROR_MESSAGES.AUCTION_ASSERTION_FAILED,
        );
      }
    }
    if (auctionAssertion.currencyRaised !== undefined) {
      if (!this.validateEquality(auctionAssertion.currencyRaised, auctionState.currencyRaised)) {
        this.throwAuctionAssertionError(
          auctionAssertion.currencyRaised,
          auctionState.currencyRaised,
          "currencyRaised",
          ERROR_MESSAGES.AUCTION_ASSERTION_FAILED,
        );
      }
    }
    if (auctionAssertion.latestCheckpoint !== undefined) {
      this.validateAuctionCheckpointAssertion(auctionAssertion.latestCheckpoint, auctionState.latestCheckpoint);
    }
  }

  async validateAuctionCheckpointAssertion(
    checkpointAssertion: InternalCheckpointStruct,
    stateCheckpoint: CheckpointStruct,
  ): Promise<void> {
    if (checkpointAssertion.clearingPrice !== undefined) {
      if (!this.validateEquality(checkpointAssertion.clearingPrice, stateCheckpoint.clearingPrice)) {
        this.throwAuctionAssertionError(
          checkpointAssertion.clearingPrice,
          stateCheckpoint.clearingPrice,
          "clearingPrice",
          ERROR_MESSAGES.AUCTION_ASSERTION_FAILED,
        );
      }
    }
    if (checkpointAssertion.currencyRaisedAtClearingPriceQ96_X7 !== undefined) {
      if (
        !this.validateEquality(
          checkpointAssertion.currencyRaisedAtClearingPriceQ96_X7,
          stateCheckpoint.currencyRaisedAtClearingPriceQ96_X7,
        )
      ) {
        this.throwAuctionAssertionError(
          checkpointAssertion.currencyRaisedAtClearingPriceQ96_X7,
          stateCheckpoint.currencyRaisedAtClearingPriceQ96_X7,
          "currencyRaisedAtClearingPriceQ96_X7",
          ERROR_MESSAGES.AUCTION_ASSERTION_FAILED,
        );
      }
    }
    if (checkpointAssertion.cumulativeMpsPerPrice !== undefined) {
      if (!this.validateEquality(checkpointAssertion.cumulativeMpsPerPrice, stateCheckpoint.cumulativeMpsPerPrice)) {
        this.throwAuctionAssertionError(
          checkpointAssertion.cumulativeMpsPerPrice,
          stateCheckpoint.cumulativeMpsPerPrice,
          "cumulativeMpsPerPrice",
          ERROR_MESSAGES.AUCTION_ASSERTION_FAILED,
        );
      }
    }
    if (checkpointAssertion.cumulativeMps !== undefined) {
      if (!this.validateEquality(checkpointAssertion.cumulativeMps, stateCheckpoint.cumulativeMps)) {
        this.throwAuctionAssertionError(
          checkpointAssertion.cumulativeMps,
          stateCheckpoint.cumulativeMps,
          "cumulativeMps",
          ERROR_MESSAGES.AUCTION_ASSERTION_FAILED,
        );
      }
    }
    if (checkpointAssertion.prev !== undefined) {
      if (!this.validateEquality(checkpointAssertion.prev, stateCheckpoint.prev)) {
        this.throwAuctionAssertionError(
          checkpointAssertion.prev,
          stateCheckpoint.prev,
          "prev",
          ERROR_MESSAGES.AUCTION_ASSERTION_FAILED,
        );
      }
    }
    if (checkpointAssertion.next !== undefined) {
      if (!this.validateEquality(checkpointAssertion.next, stateCheckpoint.next)) {
        this.throwAuctionAssertionError(
          checkpointAssertion.next,
          stateCheckpoint.next,
          "next",
          ERROR_MESSAGES.AUCTION_ASSERTION_FAILED,
        );
      }
    }
  }

  async throwAuctionAssertionError(
    expected: any,
    actual: any,
    field: string,
    errorFunction: (expected: any, actual: any, field?: string, variance?: string) => string,
  ): Promise<void> {
    const variance = typeof expected === "object" && "variation" in expected ? expected.variation : undefined;
    throw new Error(
      errorFunction(
        typeof expected === "object" && "amount" in expected ? expected.amount : expected,
        actual,
        field,
        variance,
      ),
    );
  }

  /**
   * Validates event assertions by checking if specific events were emitted in the current block.
   * @param eventAssertion - Array of event assertions to validate
   * @throws Error if any event assertion fails or block is not found
   */
  async validateEventAssertions(eventAssertion: EventAssertion[]): Promise<void> {
    for (const assertion of eventAssertion) {
      console.log(LOG_PREFIXES.INFO, "Event assertion validation for event:", assertion.eventName);

      // Get the current block to check for events
      const currentBlock = await hre.ethers.provider.getBlockNumber();
      const block = await hre.ethers.provider.getBlock(currentBlock);

      if (!block) {
        throw new Error(ERROR_MESSAGES.BLOCK_NOT_FOUND(currentBlock));
      }

      const eventFound = await this.checkForEventInBlock(block, assertion);

      if (!eventFound) {
        throw new Error(ERROR_MESSAGES.EVENT_ASSERTION_FAILED(assertion.eventName));
      }

      console.log(LOG_PREFIXES.SUCCESS, "Event assertion validated:", assertion.eventName);
    }
  }

  /**
   * Checks if a specific event was emitted in a given block.
   * @param block - The block to search for events
   * @param assertion - Event assertion containing event name and expected arguments
   * @returns True if the event is found with matching arguments, false otherwise
   */
  private async checkForEventInBlock(block: any, assertion: EventAssertion): Promise<boolean> {
    // Check all transactions in the block for the event
    console.log(LOG_PREFIXES.INFO, "Checking for event in block:", block.number);
    for (const txHash of block.transactions) {
      const receipt = await hre.ethers.provider.getTransactionReceipt(txHash);

      if (!receipt) continue;
      // Check each log in the transaction
      for (const log of receipt.logs) {
        try {
          // Try to decode the log using the auction contract interface
          const parsedLog = this.auction.interface.parseLog({
            topics: log.topics,
            data: log.data,
          });
          if (parsedLog && parsedLog.name === assertion.eventName) {
            // Check if the event arguments match expected values
            const matches = this.checkEventArguments(parsedLog.args, assertion.expectedArgs);
            if (matches) {
              return true;
            }
          }
          if (parsedLog) {
            let joinedEvent = parsedLog.name + "(" + parsedLog.args.join(",") + ")";
            if (joinedEvent.toLowerCase().includes(assertion.eventName.toLowerCase())) {
              return true;
            }
          }
        } catch (error) {
          // Log parsing failed, continue to next log
          continue;
        }
      }
    }

    return false;
  }

  /**
   * Checks if event arguments match the expected values.
   * @param actualArgs - Array of actual event arguments from the contract
   * @param expectedArgs - Object containing expected argument values
   * @returns True if all expected arguments are found in the actual arguments, false otherwise
   */
  private checkEventArguments(actualArgs: any, expectedArgs?: Record<string, any>): boolean {
    if (!expectedArgs || Object.keys(expectedArgs).length === 0) {
      return true; // No args to check, just event name match is enough
    }
    for (const [, expectedValue] of Object.entries(expectedArgs)) {
      let contains = actualArgs.some((value: any) => value == expectedValue).length > 0;
      if (!contains) {
        return false;
      }
    }
    return true;
  }

  /**
   * Retrieves the current auction state from the contract.
   * @returns AuctionState object containing isGraduated, clearingPrice, currencyRaised, latestCheckpoint, and currentBlock
   */
  async getAuctionState(): Promise<AuctionState> {
    const [isGraduated, clearingPrice, currencyRaised, latestCheckpoint, currentBlock] = await Promise.all([
      this.auction.isGraduated(),
      this.auction.clearingPrice(),
      this.auction.currencyRaised(),
      this.auction.latestCheckpoint(),
      hre.ethers.provider.getBlockNumber(),
    ]);

    return {
      isGraduated,
      clearingPrice,
      currencyRaised,
      latestCheckpoint,
      currentBlock,
    };
  }

  /**
   * Retrieves the current state of a bidder including token and currency balances.
   * @param bidderAddress - The address of the bidder to check
   * @returns BidderState object containing address, tokenBalance, and currencyBalance
   */
  async getBidderState(bidderAddress: Address): Promise<BidderState> {
    if (this.token == undefined) {
      throw new Error(ERROR_MESSAGES.TOKEN_UNSET);
    }
    if (this.currency === undefined) {
      throw new Error(ERROR_MESSAGES.CURRENCY_UNSET);
    }
    const tokenBalance = this.token ? await this.token.balanceOf(bidderAddress) : 0n;
    const currencyBalance = this.currency ? await this.currency.balanceOf(bidderAddress) : 0n;

    return {
      address: bidderAddress,
      tokenBalance: tokenBalance.toString(),
      currencyBalance: currencyBalance.toString(),
    };
  }
}
