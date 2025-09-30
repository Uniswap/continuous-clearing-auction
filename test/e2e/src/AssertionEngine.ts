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
import { ZERO_ADDRESS, LOG_PREFIXES } from "./constants";
import { CheckpointStruct } from "../../../typechain-types/out/Auction";
import hre from "hardhat";

// NOTE: Different from interface defined in the schema as it uses bigint since this comes directly from the contract
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

  async resolveTokenAddress(tokenIdentifier: string): Promise<string> {
    if (tokenIdentifier.startsWith("0x")) {
      return tokenIdentifier; // It's already an address
    }
    // Look up by name in the deployed tokens (from AuctionDeployer)
    const tokenContract = this.auctionDeployer.getTokenByName(tokenIdentifier);
    if (tokenContract) {
      return await tokenContract.getAddress();
    }
    throw new Error(`Token with identifier ${tokenIdentifier} not found.`);
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

  private validateEquality(expected: any, actual: any): boolean {
    if (expected && typeof expected === "object") {
      let keys = Object.keys(expected);
      if (keys.length !== 2 || !keys.includes("amount") || !keys.includes("variation")) {
        throw new Error(`Can only validate equality for non-object types`);
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

  async validateBalanceAssertion(assertion: BalanceAssertion): Promise<void> {
    const { address, token, expected, variance } = assertion;

    let actualBalance: bigint;
    const expectedBalance = BigInt(expected);

    const resolvedTokenAddress = await this.resolveTokenAddress(token);

    if (resolvedTokenAddress === ZERO_ADDRESS) {
      // Native currency
      actualBalance = await hre.ethers.provider.getBalance(address);
      console.log(
        LOG_PREFIXES.ASSERTION,
        "Native currency balance check:",
        address,
        "has",
        actualBalance,
        "wei, expected",
        expectedBalance,
      );
    } else {
      // ERC20 token
      const tokenContract = await hre.ethers.getContractAt("IERC20Minimal", resolvedTokenAddress);
      actualBalance = await tokenContract.balanceOf(address);
      console.log(
        LOG_PREFIXES.ASSERTION,
        "ERC20 token balance check:",
        address,
        "has",
        actualBalance,
        "of",
        token,
        ", expected",
        expectedBalance,
      );
    }
    let expectedVariance = variance ? this.parseVariance(variance) : 0;
    if (!this.isWithinVariance(actualBalance, expectedBalance, expectedVariance)) {
      throw new Error(
        `Balance assertion failed for ${address} token ${token}. Expected ${expectedBalance} (±${variance}), got ${actualBalance}`,
      );
    }
    console.log(LOG_PREFIXES.SUCCESS, "Assertion validated (within variance of", variance + ")");
  }

  async validateTotalSupplyAssertion(totalSupplyAssertion: TotalSupplyAssertion[]): Promise<void> {
    for (const assertion of totalSupplyAssertion) {
      const tokenAddress = await this.resolveTokenAddress(assertion.token);
      const token = await this.auctionDeployer.getTokenByAddress(tokenAddress);

      if (!token) {
        throw new Error(`Token not found for address: ${tokenAddress}`);
      }
      const _addr = await token.getAddress();
      console.log(LOG_PREFIXES.INFO, "Token address for totalSupply():", _addr);
      const actualSupply = await token.totalSupply();
      const expectedSupply = BigInt(assertion.expected);

      console.log(
        LOG_PREFIXES.ASSERTION,
        "Total supply check:",
        tokenAddress,
        "has",
        actualSupply.toString(),
        "total supply, expected",
        expectedSupply.toString(),
      );

      if (actualSupply !== expectedSupply) {
        throw new Error(
          `Total supply assertion failed: expected ${expectedSupply.toString()}, got ${actualSupply.toString()}`,
        );
      }
    }
  }

  async validateAuctionAssertion(auctionAssertions: AuctionAssertion[]): Promise<void> {
    for (const assertion of auctionAssertions) {
      console.log(LOG_PREFIXES.INFO, "Auction assertion validation");

      // Get the current auction state
      const auctionState = await this.getAuctionState();

      for (const key of Object.keys(assertion)) {
        if (key === "type") continue;
        if (key === "latestCheckpoint") continue;
        let expected = assertion[key as keyof AuctionAssertion];
        if (expected != undefined && expected != null) {
          if (!this.validateEquality(expected, auctionState[key as keyof AuctionState])) {
            throw new Error(
              `Auction assertion failed: expected ${assertion[key as keyof AuctionAssertion]}, got ${
                auctionState[key as keyof AuctionState]
              }`,
            );
          }
        }
      }

      if (assertion.latestCheckpoint) {
        for (const key of Object.keys(assertion.latestCheckpoint)) {
          if (key === "type") continue;
          let expected = assertion.latestCheckpoint[key as keyof CheckpointStruct];
          if (expected != undefined && expected != null) {
            if (!this.validateEquality(expected, auctionState.latestCheckpoint[key as keyof CheckpointStruct])) {
              throw new Error(
                `Auction latestCheckpoint assertion failed: expected ${
                  assertion.latestCheckpoint[key as keyof CheckpointStruct]
                }, got ${auctionState.latestCheckpoint[key as keyof CheckpointStruct]}`,
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

  async validateEventAssertion(eventAssertion: EventAssertion[]): Promise<void> {
    for (const assertion of eventAssertion) {
      console.log(LOG_PREFIXES.INFO, "Event assertion validation for event:", assertion.eventName);

      // Get the current block to check for events
      const currentBlock = await hre.ethers.provider.getBlockNumber();
      const block = await hre.ethers.provider.getBlock(currentBlock);

      if (!block) {
        throw new Error(`Block ${currentBlock} not found`);
      }

      // Get all transaction receipts for this block
      const eventFound = await this.checkForEventInBlock(block, assertion);

      if (!eventFound) {
        throw new Error(`Event assertion failed: Event '${assertion.eventName}' not found with expected arguments`);
      }

      console.log(LOG_PREFIXES.SUCCESS, "Event assertion validated:", assertion.eventName);
    }
  }

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
