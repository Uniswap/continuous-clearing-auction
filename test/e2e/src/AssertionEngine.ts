import { AssertionInterfaceType, BalanceAssertion, PoolAssertion, EventAssertion, TotalSupplyAssertion, Assertion, Address } from '../schemas/TestInteractionSchema';
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
    } else {
      // TODO: Implement other assertion interfaces (TotalSupplyAssertion, EventAssertion, PoolAssertion, etc.)
      console.log(`   ⚠️  Unsupported assertion interface: ${assertion.type}`);
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
    // TODO: implement this validation
    console.log(`   ⚠️  Total supply assertion validation not yet implemented`);
  }

  async validatePoolAssertion(poolAssertions: PoolAssertion[]): Promise<void> {
    // TODO: implement this validation
    console.log(`   ⚠️  Pool assertion validation not yet implemented`);
  }

  async validateEventAssertion(eventAssertion: EventAssertion[]): Promise<void> {
    // TODO: implement this validation
    console.log(`   ⚠️  Event assertion validation not yet implemented`);
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
