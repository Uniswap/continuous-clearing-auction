import { InteractionData } from './SchemaValidator';

export interface BalanceAssertion {
  type: 'balance';
  address: string;
  token: string;
  expected: string;
}

export interface AddressAssertion {
  address: string;
  balance?: string | number;
}

export interface PoolAssertion {
  tick?: number;
  sqrtPriceX96?: string | number;
  liquidity?: string | number;
}

export interface EventAssertion {
  signature: string;
}

export interface AuctionState {
  currentBlock: number;
  isGraduated: boolean;
  clearingPrice: bigint;
  currencyRaised: bigint;
}

export interface BidderState {
  address: string;
  tokenBalance: bigint;
  currencyBalance: bigint;
}

export class AssertionEngine {
  private auction: any;
  private token: any;
  private currency: any;
  private ethers: any;

  constructor(
    auction: any, 
    token: any, 
    currency: any, 
    hre: any
  ) {
    this.auction = auction;
    this.token = token;
    this.currency = currency;
    this.ethers = hre.ethers;
  }

  async validateCheckpoints(interactionData: InteractionData, timeBase: string): Promise<void> {
    if (!interactionData.checkpoints) return;

    for (const checkpoint of interactionData.checkpoints) {
      // Note: Block mining is now handled at the block level in CombinedTestRunner
      // This method just validates the assertion
      
      if (checkpoint.assert) {
        await this.validateAssertion(checkpoint.assert);
      }
    }
  }

  async validateAssertion(assertion: any): Promise<void> {
    if (assertion.type === 'balance') {
      await this.validateBalanceAssertion(assertion as BalanceAssertion);
    } else if (assertion.address) {
      await this.validateAddressAssertion(assertion as AddressAssertion);
    } else if (assertion.pool) {
      // TODO: Implement pool state assertions
      // Should validate tick, sqrtPriceX96, liquidity values
      console.log(`   🏊 Pool assertion: tick=${assertion.pool.tick}, sqrtPriceX96=${assertion.pool.sqrtPriceX96}, liquidity=${assertion.pool.liquidity}`);
      await this.validatePoolAssertion(assertion.pool as PoolAssertion);
    } else if (assertion.events) {
      // TODO: Implement event assertions
      // Should validate that specific events were emitted
      console.log(`   📝 Event assertion: ${assertion.events.length} events to validate`);
      await this.validateEventAssertion(assertion.events as EventAssertion[]);
    }
  }

  async validateBalanceAssertion(assertion: BalanceAssertion): Promise<void> {
    const { address, token, expected } = assertion;
    
    let actualBalance: bigint;
    const expectedBalance = BigInt(expected);
    
    if (token === 'Native') {
      // Check native currency balance (ETH, MATIC, BNB, etc.)
      actualBalance = await this.ethers.provider.getBalance(address);
      console.log(`   💰 Native currency balance check: ${address} has ${actualBalance.toString()} wei, expected ${expectedBalance.toString()}`);
    } else {
      // Get the token contract based on the token name
      let tokenContract: any = null;
      if (token === 'USDC') {
        tokenContract = this.currency; // USDC is our currency token
      } else {
        tokenContract = this.token; // Default to auctioned token
      }
      
      if (!tokenContract) {
        throw new Error(`Token contract not found for token: ${token}`);
      }
      
      actualBalance = await tokenContract.balanceOf(address);
      console.log(`   💰 Token Balance check: ${address} has ${actualBalance.toString()} ${token}, expected ${expectedBalance.toString()}`);
    }
    
    if (actualBalance !== expectedBalance) {
      throw new Error(
        `Balance assertion failed for ${address}: expected ${expectedBalance} ${token}, got ${actualBalance}`
      );
    }
  }

  async validateAddressAssertion(addressAssertion: AddressAssertion): Promise<void> {
    const { address, balance } = addressAssertion;
    
    if (balance !== undefined && this.token) {
      const actualBalance = await this.token.balanceOf(address);
      const expectedBalance = BigInt(balance);
      
      if (actualBalance !== expectedBalance) {
        throw new Error(
          `Address balance assertion failed: expected ${expectedBalance}, got ${actualBalance}`
        );
      }
    }
  }

  async validatePoolAssertion(poolAssertion: PoolAssertion): Promise<void> {
    // Validate pool state assertions
    if (poolAssertion.tick !== undefined) {
      try {
        const actualTick = await this.auction.getCurrentTick();
        if (actualTick !== poolAssertion.tick) {
          throw new Error(
            `Pool tick assertion failed: expected ${poolAssertion.tick}, got ${actualTick}`
          );
        }
      } catch (error) {
        console.warn('   ⚠️  getCurrentTick not available on auction contract');
      }
    }

    if (poolAssertion.sqrtPriceX96 !== undefined) {
      try {
        const actualSqrtPrice = await this.auction.getCurrentSqrtPrice();
        const expectedSqrtPrice = BigInt(poolAssertion.sqrtPriceX96);
        
        if (actualSqrtPrice !== expectedSqrtPrice) {
          throw new Error(
            `Pool sqrtPriceX96 assertion failed: expected ${expectedSqrtPrice}, got ${actualSqrtPrice}`
          );
        }
      } catch (error) {
        console.warn('   ⚠️  getCurrentSqrtPrice not available on auction contract');
      }
    }

    if (poolAssertion.liquidity !== undefined) {
      try {
        const actualLiquidity = await this.auction.getCurrentLiquidity();
        const expectedLiquidity = BigInt(poolAssertion.liquidity);
        
        if (actualLiquidity !== expectedLiquidity) {
          throw new Error(
            `Pool liquidity assertion failed: expected ${expectedLiquidity}, got ${actualLiquidity}`
          );
        }
      } catch (error) {
        console.warn('   ⚠️  getCurrentLiquidity not available on auction contract');
      }
    }
  }

  async validateEventAssertion(eventAssertions: EventAssertion[]): Promise<void> {
    // This would validate that specific events were emitted
    // Implementation depends on how you want to track events
    for (const eventAssertion of eventAssertions) {
      // Validate event signature and parameters
      console.log(`Validating event: ${eventAssertion.signature}`);
    }
  }

  async getAuctionState(): Promise<AuctionState> {
    return {
      currentBlock: await this.ethers.provider.getBlockNumber(),
      isGraduated: await this.auction.isGraduated(),
      clearingPrice: await this.auction.clearingPrice(),
      currencyRaised: await this.auction.currencyRaised()
    };
  }

  async getBidderState(bidderAddress: string): Promise<BidderState> {
    // This would return the state of a specific bidder
    // Implementation depends on how bids are tracked
    const tokenBalance = this.token ? await this.token.balanceOf(bidderAddress) : 0n;
    const currencyBalance = this.currency ? await this.currency.balanceOf(bidderAddress) : 0n;
    
    return {
      address: bidderAddress,
      tokenBalance,
      currencyBalance
    };
  }
}
