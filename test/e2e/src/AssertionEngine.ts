import { AssertionInterfaceType, BalanceAssertion, AuctionAssertion, EventAssertion, TotalSupplyAssertion, Assertion, Address } from '../schemas/TestInteractionSchema';
import { Contract } from "ethers";
import { TokenContract } from './types';
import { AuctionDeployer } from './AuctionDeployer';
import { ZERO_ADDRESS } from './constants';
import { CheckpointStruct } from '../../../typechain-types/out/Auction';
import hre from "hardhat";

// NOTE: Uses bigint since this comes directly from the contract
export interface AuctionState {
  currentBlock: number;
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
    if (tokenIdentifier.startsWith('0x')) {
      return tokenIdentifier; // It's already an address
    }
    // Look up by name in the deployed tokens (from AuctionDeployer)
    const tokenContract = this.auctionDeployer.getTokenByName(tokenIdentifier);
    if (tokenContract) {
      return await tokenContract.getAddress();
    }
    throw new Error(`Token with identifier ${tokenIdentifier} not found.`);
  }

  async validateBalanceAssertion(assertion: BalanceAssertion): Promise<void> {
    const { address, token, expected } = assertion;
    
    let actualBalance: bigint;
    const expectedBalance = BigInt(expected);
    
    const resolvedTokenAddress = await this.resolveTokenAddress(token);
    
    if (resolvedTokenAddress === ZERO_ADDRESS) {
      // Native currency
      actualBalance = await hre.ethers.provider.getBalance(address);
      console.log(`   💰 Native currency balance check: ${address} has ${actualBalance} wei, expected ${expectedBalance}`);
    } else {
      // ERC20 token
      const tokenContract = await hre.ethers.getContractAt('IERC20Minimal', resolvedTokenAddress);
      actualBalance = await tokenContract.balanceOf(address);
      console.log(`   💰 ERC20 token balance check: ${address} has ${actualBalance} of ${token}, expected ${expectedBalance}`);
    }
    
    if (actualBalance !== expectedBalance) {
      throw new Error(`Balance assertion failed for ${address} token ${token}. Expected ${expectedBalance}, got ${actualBalance}`);
    }
    console.log(`         ✅ Assertion validated`);
  }

  async validateTotalSupplyAssertion(totalSupplyAssertion: TotalSupplyAssertion[]): Promise<void> {
    for (const assertion of totalSupplyAssertion) {
      const tokenAddress = await this.resolveTokenAddress(assertion.token);
      const token = await this.auctionDeployer.getTokenByAddress(tokenAddress);
      
      if (!token) {
        throw new Error(`Token not found for address: ${tokenAddress}`);
      }
      const _addr = await token.getAddress();
      console.log(`   🔍 Token address for totalSupply(): ${_addr}`);
      const actualSupply = await token.totalSupply();
      const expectedSupply = BigInt(assertion.expected);
      
      console.log(`   💰 Total supply check: ${tokenAddress} has ${actualSupply.toString()} total supply, expected ${expectedSupply.toString()}`);
      
      if (actualSupply !== expectedSupply) {
        throw new Error(`Total supply assertion failed: expected ${expectedSupply.toString()}, got ${actualSupply.toString()}`);
      }
    }
  }

  async validateAuctionAssertion(auctionAssertions: AuctionAssertion[]): Promise<void> {
    for (const assertion of auctionAssertions) {
      console.log(`   🔍 Auction assertion validation`);
      
      // Get the current auction state
      const auctionState = await this.getAuctionState();
      
      for (const key of Object.keys(assertion)) {
        if (key === 'type') continue;
        if (assertion[key as keyof AuctionAssertion] != undefined &&
           assertion[key as keyof AuctionAssertion] != null &&
           auctionState[key as keyof AuctionState].toString() != assertion[key as keyof AuctionAssertion].toString()) {
          throw new Error(`Auction assertion failed: expected ${assertion[key as keyof AuctionAssertion]}, got ${auctionState[key as keyof AuctionState]}`);
        }
      }
      
      console.log(`   ✅ Auction assertion validated (partial implementation)`);
    }
  }

  async validateEventAssertion(eventAssertion: EventAssertion[]): Promise<void> {
    for (const assertion of eventAssertion) {
      console.log(`   🔍 Event assertion validation for event: ${assertion.eventName}`);
      
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
      
      console.log(`   ✅ Event assertion validated: ${assertion.eventName}`);
    }
  }
  
  private async checkForEventInBlock(block: any, assertion: EventAssertion): Promise<boolean> {
    // Check all transactions in the block for the event
    for (const txHash of block.transactions) {
      const receipt = await hre.ethers.provider.getTransactionReceipt(txHash);
      
      if (!receipt) continue;
      
      // Check each log in the transaction
      for (const log of receipt.logs) {
        try {
          // Try to decode the log using the auction contract interface
          const parsedLog = this.auction.interface.parseLog({
            topics: log.topics,
            data: log.data
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
    for (const [key, expectedValue] of Object.entries(expectedArgs)) {
      if (actualArgs[key] !== expectedValue) {
        return false;
      }
    }
    return true;
  }

  async getAuctionState(): Promise<AuctionState> {
    const [
      currentBlock,
      isGraduated,
      clearingPrice,
      currencyRaised,
      latestCheckpoint
    ] = await Promise.all([
      hre.ethers.provider.getBlockNumber(),
      this.auction.isGraduated(),
      this.auction.clearingPrice(),
      this.auction.currencyRaised(),
      this.auction.latestCheckpoint()
    ]);
    
    return {
      currentBlock,
      isGraduated,
      clearingPrice,
      currencyRaised,
      latestCheckpoint,
    };
  }

  async getBidderState(bidderAddress: Address): Promise<BidderState> {
    // TODO: This would return the state of a specific bidder. 
    // This is just a placeholder for now
    const tokenBalance = this.token ? await this.token.balanceOf(bidderAddress) : 0n;
    const currencyBalance = this.currency ? await this.currency.balanceOf(bidderAddress) : 0n;
    
    return {
      address: bidderAddress,
      tokenBalance: tokenBalance.toString(),
      currencyBalance: currencyBalance.toString(),
    };
  }
}
