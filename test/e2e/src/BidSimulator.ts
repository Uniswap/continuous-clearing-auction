import { ActionType, TestInteractionData, Group, BidData, Side, AmountType, PriceType, AdminActionMethod, Address } from '../schemas/TestInteractionSchema';
import { Contract } from "ethers";
import hre from "hardhat";

export interface InternalBidData {
  bidData: BidData;
  bidder: string;
  type: 'named' | 'group';
  group?: string;
}

export class BidSimulator {
  private auction: Contract;
  private currency: Contract;
  private labelMap: Map<string, string> = new Map();
  private groupBidders: Map<string, string[]> = new Map();

  constructor(
    auction: Contract, 
    currency: Contract
  ) {
    this.auction = auction;
    this.currency = currency;
  }

  async setupLabels(interactionData: TestInteractionData): Promise<void> {
    // Map symbolic labels to actual addresses
    this.labelMap.set('Pool', await this.auction.getAddress());
    this.labelMap.set('Auction', await this.auction.getAddress());
    
    // Add named bidders
    if (interactionData.namedBidders) {
      interactionData.namedBidders.forEach(bidder => {
        this.labelMap.set(bidder.label || bidder.address, bidder.address);
      });
    }

    // Generate group bidders
    if (interactionData.groups) {
      await this.generateGroupBidders(interactionData.groups);
    }
  }

  async generateGroupBidders(groups: Group[]): Promise<void> {
    for (const group of groups) {
      const bidders: string[] = [];
      for (let i = 0; i < group.count; i++) {
        const address = hre.ethers.Wallet.createRandom().address;
        bidders.push(address);
        this.labelMap.set(`${group.labelPrefix}${i}`, address);
      }
      this.groupBidders.set(group.labelPrefix, bidders);
    }
  }

  async executeBids(interactionData: TestInteractionData): Promise<void> {
    const allBids = this.collectAllBids(interactionData);
    
    // Sort bids by block number
    allBids.sort((a, b) => a.bidData.atBlock - b.bidData.atBlock);

    for (const bid of allBids) {
      await this.executeBid(bid);
    }
  }

  collectAllBids(interactionData: TestInteractionData): InternalBidData[] {
    const bids: InternalBidData[] = [];

    // Named bidders
    if (interactionData.namedBidders) {
      interactionData.namedBidders.forEach(bidder => {
        bidder.bids.forEach(bid => {
          const internalBid = {
            bidData: bid,
            bidder: bidder.address,
            type: 'named' as const
          };
          bids.push(internalBid);
        });
        
        // TODO: Implement recurring bids support
        // bidder.recurringBids.forEach(recurringBid => {
        //   // Generate multiple bids based on startBlock, intervalBlocks, occurrences
        //   // Apply growth factors (amountFactor, priceFactor) to each occurrence
        // });
      });
    }

    // Group bidders
    if (interactionData.groups) {
      interactionData.groups.forEach(group => {
        const bidders = this.groupBidders.get(group.labelPrefix);
        if (bidders) {
          for (let round = 0; round < group.rounds; round++) {
            for (let i = 0; i < group.count; i++) {
              const bidder = bidders[i];
              const blockOffset = group.startOffsetBlocks + 
                (round * (group.rotationIntervalBlocks + group.betweenRoundsBlocks)) +
                (i * group.rotationIntervalBlocks);
              
              bids.push({
                bidData: {
                  atBlock: blockOffset,
                  amount: group.amount,
                  price: group.price,
                  hookData: group.hookData
                },
                bidder,
                type: 'group' as const,
                group: group.labelPrefix
              });
            }
          }
        }
      });
    }

    return bids;
  }

  async executeBid(bid: InternalBidData | any): Promise<void> {
    // Note: Block mining is handled at the block level in CombinedTestRunner
    // This method just executes the bid transaction

    // Handle both old flat structure and new InternalBidData structure
    let bidData: any;
    let bidder: string;
    
    if (bid.bidData) {
      // New InternalBidData structure
      bidData = bid.bidData;
      bidder = bid.bidder;
    } else {
      // Old flat structure - convert to InternalBidData
      bidData = bid;
      bidder = bid.bidder;
    }

    const amount = await this.calculateAmount(bidData.amount);
    const price = await this.calculatePrice(bidData.price);

    // Calculate required currency amount for the bid
    const requiredCurrencyAmount = await this.calculateRequiredCurrencyAmount(
      bidData.amount.side === Side.INPUT,
      amount,
      price
    );

    console.log('   🔍 Bid details:');
    console.log('   🔍   amount:', amount.toString());
    console.log('   🔍   price:', price.toString());
    console.log('   🔍   requiredCurrencyAmount:', requiredCurrencyAmount.toString());
    console.log('   🔍   bidder:', bidder);

    try {
      // For the first bid, use tick 1 as prevTickPrice (floor price)
      // For subsequent bids, we'd need to track the previous tick
      const prevTickPrice = this.tickNumberToPriceX96(1); // Floor price tick
      
      // Impersonate the bidder account to send the transaction from their address
      await hre.network.provider.send('hardhat_impersonateAccount', [bidder]);
      
      // Get a signer for the bidder address
      const bidderSigner = await hre.ethers.getSigner(bidder);
      
      // Connect the auction contract to the bidder signer
      const auctionWithBidder = this.auction.connect(bidderSigner);
      
      let tx: any;
      if (this.currency) {
        console.log('   🔍 Using ERC20 currency - would need permit2 setup');
        // TODO: permit2 setup
        tx = await (auctionWithBidder as any).submitBid(
          price,
          bidData.amount.side === Side.INPUT,
          amount,
          bidder,
          prevTickPrice,
          bidData.hookData || '0x'
        );
      } else {
        // For ETH currency, send the required amount as msg.value
        tx = await (auctionWithBidder as any).submitBid(
          price,
          bidData.amount.side === Side.INPUT,
          amount,
          bidder,
          prevTickPrice,
          bidData.hookData || '0x',
          { value: requiredCurrencyAmount }
        );
      }

      await tx.wait();
      
      // Stop impersonating the account
      await hre.network.provider.send('hardhat_stopImpersonatingAccount', [bidder]);
      
    } catch (error: any) {
      // Stop impersonating the account even if there's an error
      try {
        await hre.network.provider.send('hardhat_stopImpersonatingAccount', [bidder]);
      } catch (stopError) {
        // Ignore stop impersonation errors
      }
      
      if (bidData.expectRevert) {
        // Expected revert - validate the revert data if specified
        await this.validateExpectedRevert(error, bidData.expectRevert);
        return;
      }
      throw error;
    }
    // TODO: check transaction receipt for revert
  }

  async validateExpectedRevert(error: any, expectedRevert: string): Promise<void> {
    // TODO: decode reason from revert data
    // Extract the revert data string from the error
    const actualRevertData = error?.data || error?.error?.data || error?.info?.data || '';
    
    // Check if the revert data contains the expected string
    if (!actualRevertData.includes(expectedRevert)) {
      throw new Error(`Expected revert data to contain "${expectedRevert}", but got: ${actualRevertData}`);
    }
    console.log(`   ✅ Expected revert validated: ${expectedRevert}`);
  }

  async calculateAmount(amountConfig: any): Promise<bigint> {
    // Implementation depends on amount type (raw, percentOfSupply, etc.)
    // This is a simplified version
    if (amountConfig.type === AmountType.RAW) {
      return BigInt(amountConfig.value);
    }
    
    // TODO: Implement percentOfSupply calculation
    // Should calculate percentage of total token supply
    if (amountConfig.type === AmountType.PERCENT_OF_SUPPLY) {
      // const totalSupply = await this.token.totalSupply();
      // return (totalSupply * BigInt(amountConfig.value)) / 100n;
    }
    
    // TODO: Implement basisPoints calculation
    // Should calculate basis points (1/10000) of total supply
    if (amountConfig.type === AmountType.BASIS_POINTS) {
      // const totalSupply = await this.token.totalSupply();
      // return (totalSupply * BigInt(amountConfig.value)) / 10000n;
    }
    
    // TODO: Implement percentOfGroup calculation
    // Should calculate percentage of group total
    if (amountConfig.type === AmountType.PERCENT_OF_GROUP) {
      // Implementation depends on group context
    }
    
    // TODO: Implement amount variation
    // if (amountConfig.variation) {
    //   const variation = BigInt(amountConfig.variation);
    //   const randomVariation = Math.floor(Math.random() * (2 * Number(variation) + 1)) - Number(variation);
    //   value = value + BigInt(randomVariation);
    //   if (value < 0n) value = 0n;
    // }
    
    return BigInt(amountConfig.value);
  }

  async calculatePrice(priceConfig: any): Promise<bigint> {
    if (priceConfig.type === PriceType.TICK) {
      // Convert tick to actual price using the same logic as the Foundry tests
      return this.tickNumberToPriceX96(parseInt(priceConfig.value.toString()));
    }
    
    // TODO: Implement price variation
    // if (priceConfig.variation) {
    //   const variation = BigInt(priceConfig.variation);
    //   const randomVariation = Math.floor(Math.random() * (2 * Number(variation) + 1)) - Number(variation);
    //   value = value + BigInt(randomVariation);
    //   if (value < 0n) value = 0n;
    // }
    
    return BigInt(priceConfig.value);
  }

  tickNumberToPriceX96(tickNumber: number): bigint {
    // This mirrors the logic from AuctionBaseTest.sol
    const FLOOR_PRICE = 1000n * (2n ** 96n); // 1000 * 2^96
    const TICK_SPACING = 100n; // From our setup (matches Foundry test)
    
    return ((FLOOR_PRICE >> 96n) + (BigInt(tickNumber) - 1n) * TICK_SPACING) << 96n;
  }

  async calculateRequiredCurrencyAmount(exactIn: boolean, amount: bigint, maxPrice: bigint): Promise<bigint> {
    // This mirrors the BidLib.inputAmount logic
    if (exactIn) {
      // For exactIn bids, the amount is in currency units
      return amount;
    } else {
      // For non-exactIn bids, calculate amount * maxPrice / Q96
      const Q96 = BigInt(2) ** BigInt(96);
      return (amount * maxPrice) / Q96;
    }
  }

  async executeActions(interactionData: TestInteractionData): Promise<void> {
    if (!interactionData.actions) return;

    for (const action of interactionData.actions) {
      if (action.type === ActionType.TRANSFER_ACTION) {
        await this.executeTransfers(action.interactions);
      } else if (action.type === ActionType.ADMIN_ACTION) {
        await this.executeAdminActions(action.interactions);
      }
    }
  }

  async executeTransfers(transferInteractions: any[]): Promise<void> {
    // TODO: Implement transfer actions
    // This should handle token transfers between addresses
    // Support for both ERC20 tokens and native currency
    // Should resolve label references for 'to' addresses
    
    for (const interactionGroup of transferInteractions) {
      for (const interaction of interactionGroup) {
        // Note: Block mining is handled at the block level in CombinedTestRunner
        
        const { from, to, token, amount } = interaction.value;
        const toAddress = this.labelMap.get(to) || to;
        const amountValue = await this.calculateAmount(amount);

        // TODO: Execute the transfer
        // Implementation depends on token type (ERC20 vs ETH)
        // Need to handle token name references vs addresses
        console.log(`   🔄 Transfer action: ${amountValue} from ${from} to ${toAddress} (token: ${token})`);
      }
    }
  }

  async executeAdminActions(adminInteractions: any[]): Promise<void> {
    // TODO: Implement full admin actions support
    // Currently only supports sweepCurrency and sweepUnsoldTokens
    // Need to implement: pause, unpause, setFee, setParam, setValidationHook
    
    for (const interactionGroup of adminInteractions) {
      for (const interaction of interactionGroup) {
        // Note: Block mining is handled at the block level in CombinedTestRunner
        
        const { kind } = interaction.value;
        if (kind === AdminActionMethod.SWEEP_CURRENCY) {
          await this.auction.sweepCurrency();
        } else if (kind === AdminActionMethod.SWEEP_UNSOLD_TOKENS) {
          await this.auction.sweepUnsoldTokens();
        } 
      }
    }
  }
}
