class AssertionEngine {
  constructor(auction, token, currency, ethers) {
    this.auction = auction;
    this.token = token;
    this.currency = currency;
    this.ethers = ethers;
  }

  async validateCheckpoints(interactionData, timeBase) {
    if (!interactionData.checkpoints) return;

    for (const checkpoint of interactionData.checkpoints) {
      await network.provider.send('hardhat_mine', [checkpoint.atBlock.toString()]);
      
      if (checkpoint.assert) {
        await this.validateAssertion(checkpoint.assert);
      }
    }
  }

  async validateAssertion(assertion) {
    if (assertion.type === 'balance') {
      await this.validateBalanceAssertion(assertion);
    } else if (assertion.address) {
      await this.validateAddressAssertion(assertion.address);
    } else if (assertion.pool) {
      await this.validatePoolAssertion(assertion.pool);
    } else if (assertion.events) {
      await this.validateEventAssertion(assertion.events);
    }
  }

  async validateBalanceAssertion(assertion) {
    const { address, token, expected } = assertion;
    
    let actualBalance;
    let expectedBalance = BigInt(expected);
    
    if (token === 'Native') {
      // Check native currency balance (ETH, MATIC, BNB, etc.)
      actualBalance = await this.ethers.provider.getBalance(address);
      console.log(`   💰 Native currency balance check: ${address} has ${actualBalance.toString()} wei, expected ${expectedBalance.toString()}`);
    } else {
      // Get the token contract based on the token name
      let tokenContract;
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

  async validateAddressAssertion(addressAssertion) {
    const { address, balance } = addressAssertion;
    
    if (balance !== undefined) {
      const actualBalance = await this.token.balanceOf(address);
      const expectedBalance = BigInt(balance);
      
      if (actualBalance !== expectedBalance) {
        throw new Error(
          `Address balance assertion failed: expected ${expectedBalance}, got ${actualBalance}`
        );
      }
    }
  }

  async validatePoolAssertion(poolAssertion) {
    // Validate pool state assertions
    if (poolAssertion.tick !== undefined) {
      const actualTick = await this.auction.getCurrentTick();
      if (actualTick !== poolAssertion.tick) {
        throw new Error(
          `Pool tick assertion failed: expected ${poolAssertion.tick}, got ${actualTick}`
        );
      }
    }

    if (poolAssertion.sqrtPriceX96 !== undefined) {
      const actualSqrtPrice = await this.auction.getCurrentSqrtPrice();
      const expectedSqrtPrice = BigInt(poolAssertion.sqrtPriceX96);
      
      if (actualSqrtPrice !== expectedSqrtPrice) {
        throw new Error(
          `Pool sqrtPriceX96 assertion failed: expected ${expectedSqrtPrice}, got ${actualSqrtPrice}`
        );
      }
    }

    if (poolAssertion.liquidity !== undefined) {
      const actualLiquidity = await this.auction.getCurrentLiquidity();
      const expectedLiquidity = BigInt(poolAssertion.liquidity);
      
      if (actualLiquidity !== expectedLiquidity) {
        throw new Error(
          `Pool liquidity assertion failed: expected ${expectedLiquidity}, got ${actualLiquidity}`
        );
      }
    }
  }

  async validateEventAssertion(eventAssertions) {
    // This would validate that specific events were emitted
    // Implementation depends on how you want to track events
    for (const eventAssertion of eventAssertions) {
      // Validate event signature and parameters
      console.log(`Validating event: ${eventAssertion.signature}`);
    }
  }

  async getAuctionState() {
    return {
      currentBlock: await this.ethers.provider.getBlockNumber(),
      isGraduated: await this.auction.isGraduated(),
      clearingPrice: await this.auction.clearingPrice(),
      currencyRaised: await this.auction.currencyRaised()
    };
  }

  async getBidderState(bidderAddress) {
    // This would return the state of a specific bidder
    // Implementation depends on how bids are tracked
    return {
      address: bidderAddress,
      tokenBalance: await this.token.balanceOf(bidderAddress),
      currencyBalance: await this.currency.balanceOf(bidderAddress)
    };
  }
}

module.exports = AssertionEngine;
