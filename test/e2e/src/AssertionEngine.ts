import {
  AssertionInterfaceType,
  BalanceAssertion,
  AuctionAssertion,
  EventAssertion,
  TotalSupplyAssertion,
  Assertion,
  Address,
  VariableAmount,
} from "../schemas/TestInteractionSchema";
import { Contract } from "ethers";
import { TokenContract } from "./types";
import { AuctionDeployer } from "./AuctionDeployer";
import { ZERO_ADDRESS, LOG_PREFIXES, ERROR_MESSAGES, NATIVE_TYPES, TYPE_FIELD } from "./constants";
import { CheckpointStruct } from "../../../typechain-types/out/Auction";
import { resolveTokenAddress } from "./Utils";
import hre from "hardhat";

// NOTE: Different from interface defined in the schema as it uses bigint, and no variance, since this comes directly from the contract
export interface AuctionState {
  isGraduated: boolean;
  clearingPrice: bigint;
  currencyRaised: bigint;
  latestCheckpoint: CheckpointStruct;
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
      await this.validateTotalSupplyAssertion([assertion]);
    } else if (assertion.type === AssertionInterfaceType.EVENT) {
      await this.validateEventAssertion([assertion]);
    } else if (assertion.type === AssertionInterfaceType.AUCTION) {
      await this.validateAuctionAssertion([assertion]);
    }
  }

  /**
   * Parse variance string into a ratio number.
   * Supports both percentage format (e.g., "5%") and decimal format (e.g., "0.05").
   * @param variance - Variance string in percentage or decimal format
   * @returns Ratio as a number (e.g., "5%" -> 0.05, "0.05" -> 0.05)
   */
  private parseVariance(variance: string): number {
    if (variance.endsWith("%")) {
      // Percentage: convert to ratio (e.g., "5%" -> 0.05)
      const percentage = parseFloat(variance.slice(0, -1));
      return percentage / 100;
    } else {
      // Ratio: parse as decimal (e.g., "0.05" -> 0.05)
      return parseFloat(variance);
    }
  }

  /**
   * Check if the actual balance is within the specified variance of the expected balance.
   * @param actual - The actual balance
   * @param expected - The expected balance
   * @param variance - The variance ratio (e.g., 0.05 for 5% variance)
   * @returns True if actual is within variance bounds, false otherwise
   */
  private isWithinVariance(actual: bigint, expected: bigint, variance: number): boolean {
    if (variance === 0) {
      return actual === expected;
    }

    const expectedNum = Number(expected);
    const actualNum = Number(actual);
    const varianceAmount = expectedNum * variance;
    const lowerBound = expectedNum - varianceAmount;
    const upperBound = expectedNum + varianceAmount;

    return actualNum >= lowerBound && actualNum <= upperBound;
  }

  /**
   * Validates equality between expected and actual values, supporting VariableAmount structures.
   * @param expected - Expected value (can be primitive or VariableAmount object)
   * @param actual - Actual value from the contract
   * @returns True if values are equal or within variance bounds
   * @throws Error if expected is an invalid object structure
   */
  private validateEquality(expected: any, actual: any): boolean {
    if (expected && typeof expected === NATIVE_TYPES.OBJECT) {
      let keys = Object.keys(expected);
      if (keys.length !== 2 || !keys.includes("amount") || !keys.includes("variation")) {
        throw new Error(ERROR_MESSAGES.CANNOT_VALIDATE_EQUALITY);
      }
      let expectedStruct = expected as VariableAmount;
      if (!this.isWithinVariance(actual, BigInt(expectedStruct.amount), Number(expectedStruct.variation))) {
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
    let expectedVariance = variance ? this.parseVariance(variance) : 0;
    if (!this.isWithinVariance(actualBalance, expectedBalance, expectedVariance)) {
      throw new Error(
        ERROR_MESSAGES.BALANCE_ASSERTION_FAILED(address, token, expectedBalance.toString(), actualBalance.toString()),
      );
    }
    console.log(LOG_PREFIXES.SUCCESS, "Assertion validated (within variance of", variance + ")");
  }

  /**
   * Validates total supply assertions for multiple tokens.
   * @param totalSupplyAssertion - Array of total supply assertions to validate
   * @throws Error if any total supply assertion fails or token is not found
   */
  async validateTotalSupplyAssertion(totalSupplyAssertion: TotalSupplyAssertion[]): Promise<void> {
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
  async validateAuctionAssertion(auctionAssertions: AuctionAssertion[]): Promise<void> {
    for (const assertion of auctionAssertions) {
      console.log(LOG_PREFIXES.INFO, "Auction assertion validation");

      // Get the current auction state
      const auctionState = await this.getAuctionState();

      for (const key of Object.keys(assertion)) {
        if (key === TYPE_FIELD) continue;
        if (key === "latestCheckpoint") continue;
        let expected = assertion[key as keyof AuctionAssertion];
        if (expected != undefined && expected != null) {
          if (!this.validateEquality(expected, auctionState[key as keyof AuctionState])) {
            throw new Error(
              ERROR_MESSAGES.AUCTION_ASSERTION_FAILED(
                assertion[key as keyof AuctionAssertion],
                auctionState[key as keyof AuctionState],
              ),
            );
          }
        }
      }

      if (assertion.latestCheckpoint) {
        for (const key of Object.keys(assertion.latestCheckpoint)) {
          if (key === TYPE_FIELD) continue;
          let expected = assertion.latestCheckpoint[key as keyof CheckpointStruct];
          if (expected != undefined && expected != null) {
            if (!this.validateEquality(expected, auctionState.latestCheckpoint[key as keyof CheckpointStruct])) {
              throw new Error(
                ERROR_MESSAGES.AUCTION_CHECKPOINT_ASSERTION_FAILED(
                  assertion.latestCheckpoint[key as keyof CheckpointStruct],
                  auctionState.latestCheckpoint[key as keyof CheckpointStruct],
                ),
              );
            }
          }
        }
      }
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

  /**
   * Validates event assertions by checking if specific events were emitted in the current block.
   * @param eventAssertion - Array of event assertions to validate
   * @throws Error if any event assertion fails or block is not found
   */
  async validateEventAssertion(eventAssertion: EventAssertion[]): Promise<void> {
    for (const assertion of eventAssertion) {
      console.log(LOG_PREFIXES.INFO, "Event assertion validation for event:", assertion.eventName);

      // Get the current block to check for events
      const currentBlock = await hre.ethers.provider.getBlockNumber();
      const block = await hre.ethers.provider.getBlock(currentBlock);

      if (!block) {
        throw new Error(ERROR_MESSAGES.BLOCK_NOT_FOUND(currentBlock));
      }

      // Get all transaction receipts for this block
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
  private checkEventArguments(actualArgs: any, expectedArgs: Record<string, any>): boolean {
    for (const [, expectedValue] of Object.entries(expectedArgs)) {
      let contains = false;
      softMatchLoop: for (let i = 0; i < actualArgs.length; i++) {
        if (actualArgs[i].toString() == expectedValue.toString()) {
          contains = true;
          break softMatchLoop;
        }
      }
      if (!contains) {
        return false;
      }
    }
    return true;
  }

  /**
   * Retrieves the current auction state from the contract.
   * @returns AuctionState object containing isGraduated, clearingPrice, currencyRaised, and latestCheckpoint
   */
  async getAuctionState(): Promise<AuctionState> {
    const [isGraduated, clearingPrice, currencyRaised, latestCheckpoint] = await Promise.all([
      this.auction.isGraduated(),
      this.auction.clearingPrice(),
      this.auction.currencyRaised(),
      this.auction.latestCheckpoint(),
    ]);

    return {
      isGraduated,
      clearingPrice,
      currencyRaised,
      latestCheckpoint,
    };
  }

  /**
   * Retrieves the current state of a bidder including token and currency balances.
   * @param bidderAddress - The address of the bidder to check
   * @returns BidderState object containing address, tokenBalance, and currencyBalance
   */
  async getBidderState(bidderAddress: Address): Promise<BidderState> {
    const tokenBalance = this.token ? await this.token.balanceOf(bidderAddress) : 0n;
    const currencyBalance = this.currency ? await this.currency.balanceOf(bidderAddress) : 0n;

    return {
      address: bidderAddress,
      tokenBalance: tokenBalance.toString(),
      currencyBalance: currencyBalance.toString(),
    };
  }
}
