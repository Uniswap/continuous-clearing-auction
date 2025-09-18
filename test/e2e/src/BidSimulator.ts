import { SetupData, InteractionData } from './SchemaValidator';

export interface BidData {
  atBlock: number;
  amount: {
    side: 'input' | 'output';
    type: 'raw' | 'percentOfSupply' | 'basisPoints' | 'percentOfGroup';
    value: string | number;
    variation?: string | number;
    token?: string;
  };
  price: {
    type: 'raw' | 'tick';
    value: string | number;
    variation?: string | number;
  };
  hookData?: string;
  expectRevert?: string;
  bidder: string;
  type: 'named' | 'group';
  group?: string;
}

export interface Group {
  labelPrefix: string;
  count: number;
  startOffsetBlocks: number;
  amount: any;
  price: any;
  rotationIntervalBlocks: number;
  betweenRoundsBlocks: number;
  rounds: number;
  hookData?: string;
}

export class BidSimulator {
  private hre: any;
  private ethers: any;
  private network: any;
  private auction: any;
  private token: any;
  private currency: any;
  private labelMap: Map<string, string> = new Map();
  private groupBidders: Map<string, string[]> = new Map();

  constructor(
    hre: any, 
    auction: any, 
    token: any, 
    currency: any
  ) {
    this.hre = hre;
    this.ethers = hre.ethers;
    this.network = hre.network;
    this.auction = auction;
    this.token = token;
    this.currency = currency;
  }

  async setupLabels(setupData: SetupData, interactionData: InteractionData): Promise<void> {
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
        const address = this.ethers.Wallet.createRandom().address;
        bidders.push(address);
        this.labelMap.set(`${group.labelPrefix}${i}`, address);
      }
      this.groupBidders.set(group.labelPrefix, bidders);
    }
  }

  async executeBids(interactionData: InteractionData, timeBase: string): Promise<void> {
    const allBids = this.collectAllBids(interactionData, timeBase);
    
    // Sort bids by block number
    allBids.sort((a, b) => a.atBlock - b.atBlock);

    for (const bid of allBids) {
      await this.executeBid(bid);
    }
  }

  collectAllBids(interactionData: InteractionData, timeBase: string): BidData[] {
    const bids: BidData[] = [];

    // Named bidders
    if (interactionData.namedBidders) {
      interactionData.namedBidders.forEach(bidder => {
        bidder.bids.forEach(bid => {
          bids.push({
            ...bid,
            bidder: bidder.address,
            type: 'named'
          });
        });
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
                atBlock: blockOffset,
                amount: group.amount,
                price: group.price,
                hookData: group.hookData,
                bidder,
                type: 'group',
                group: group.labelPrefix
              });
            }
          }
        }
      });
    }

    return bids;
  }

  async executeBid(bid: BidData): Promise<void> {
    // Note: Block mining is handled at the block level in CombinedTestRunner
    // This method just executes the bid transaction

    const amount = await this.calculateAmount(bid.amount);
    const price = await this.calculatePrice(bid.price);

    // Calculate required currency amount for the bid
    const requiredCurrencyAmount = await this.calculateRequiredCurrencyAmount(
      bid.amount.side === 'input',
      amount,
      price
    );

    console.log('   🔍 Bid details:');
    console.log('   🔍   amount:', amount.toString());
    console.log('   🔍   price:', price.toString());
    console.log('   🔍   requiredCurrencyAmount:', requiredCurrencyAmount.toString());
    console.log('   🔍   bidder:', bid.bidder);

    try {
      // For the first bid, use tick 1 as prevTickPrice (floor price)
      // For subsequent bids, we'd need to track the previous tick
      const prevTickPrice = this.tickNumberToPriceX96(1); // Floor price tick
      
      // Impersonate the bidder account to send the transaction from their address
      await this.network.provider.send('hardhat_impersonateAccount', [bid.bidder]);
      
      // Get a signer for the bidder address
      const bidderSigner = await this.ethers.getSigner(bid.bidder);
      
      // Connect the auction contract to the bidder signer
      const auctionWithBidder = this.auction.connect(bidderSigner);
      
      let tx: any;
      if (this.currency) {
        console.log('   🔍 Using ERC20 currency - would need permit2 setup');
        // For ERC20 tokens, we would need permit2 setup
        // For now, we'll skip this and let the auction handle it
        tx = await (auctionWithBidder as any).submitBid(
          price,
          bid.amount.side === 'input',
          amount,
          bid.bidder,
          prevTickPrice,
          bid.hookData || '0x'
        );
      } else {
        // For ETH currency, send the required amount as msg.value
        tx = await (auctionWithBidder as any).submitBid(
          price,
          bid.amount.side === 'input',
          amount,
          bid.bidder,
          prevTickPrice,
          bid.hookData || '0x',
          { value: requiredCurrencyAmount }
        );
      }

      await tx.wait();
      
      // Stop impersonating the account
      await this.network.provider.send('hardhat_stopImpersonatingAccount', [bid.bidder]);
      
    } catch (error: any) {
      // Stop impersonating the account even if there's an error
      try {
        await this.network.provider.send('hardhat_stopImpersonatingAccount', [bid.bidder]);
      } catch (stopError) {
        // Ignore stop impersonation errors
      }
      
      if (bid.expectRevert) {
        // Expected revert - this is fine
        return;
      }
      throw error;
    }
  }

  async calculateAmount(amountConfig: any): Promise<bigint> {
    // Implementation depends on amount type (raw, percentOfSupply, etc.)
    // This is a simplified version
    if (amountConfig.type === 'raw') {
      return BigInt(amountConfig.value);
    }
    // Add other amount calculation logic here
    return BigInt(amountConfig.value);
  }

  async calculatePrice(priceConfig: any): Promise<bigint> {
    if (priceConfig.type === 'tick') {
      // Convert tick to actual price using the same logic as the Foundry tests
      return this.tickNumberToPriceX96(parseInt(priceConfig.value.toString()));
    }
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
      // For exactIn bids, the amount is in token units
      // For ETH currency, both token and currency have 18 decimals, so no conversion needed
      // For ERC20 currency, we would need to convert from token decimals to currency decimals
      return amount;
    } else {
      // For non-exactIn bids, calculate amount * maxPrice / Q96
      const Q96 = BigInt(2) ** BigInt(96);
      return (amount * maxPrice) / Q96;
    }
  }

  async executeActions(interactionData: InteractionData, timeBase: string): Promise<void> {
    if (!interactionData.actions) return;

    for (const action of interactionData.actions) {
      if (action.type === 'Transfer') {
        await this.executeTransfers(action.interactions);
      } else if (action.type === 'AdminAction') {
        await this.executeAdminActions(action.interactions);
      }
    }
  }

  async executeTransfers(transferInteractions: any[]): Promise<void> {
    for (const interactionGroup of transferInteractions) {
      for (const interaction of interactionGroup) {
        // Note: Block mining is handled at the block level in CombinedTestRunner
        
        const { from, to, token, amount } = interaction.value;
        const toAddress = this.labelMap.get(to) || to;
        const amountValue = await this.calculateAmount(amount);

        // Execute the transfer
        // Implementation depends on token type (ERC20 vs ETH)
      }
    }
  }

  async executeAdminActions(adminInteractions: any[]): Promise<void> {
    for (const interactionGroup of adminInteractions) {
      for (const interaction of interactionGroup) {
        // Note: Block mining is handled at the block level in CombinedTestRunner
        
        const { kind } = interaction.value;
        if (kind === 'sweepCurrency') {
          await this.auction.sweepCurrency();
        } else if (kind === 'sweepUnsoldTokens') {
          await this.auction.sweepUnsoldTokens();
        }
      }
    }
  }
}
