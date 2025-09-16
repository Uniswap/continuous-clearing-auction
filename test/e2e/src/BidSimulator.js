const { ethers } = require('hardhat');
const { network } = require('hardhat');

class BidSimulator {
  constructor(auction, token, currency) {
    this.auction = auction;
    this.token = token;
    this.currency = currency;
    this.labelMap = new Map();
    this.groupBidders = new Map();
  }

  async setupLabels(setupData, interactionData) {
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

  async generateGroupBidders(groups) {
    for (const group of groups) {
      const bidders = [];
      for (let i = 0; i < group.count; i++) {
        const address = ethers.Wallet.createRandom().address;
        bidders.push(address);
        this.labelMap.set(`${group.labelPrefix}${i}`, address);
      }
      this.groupBidders.set(group.labelPrefix, bidders);
    }
  }

  async executeBids(interactionData, timeBase) {
    const allBids = this.collectAllBids(interactionData, timeBase);
    
    // Sort bids by block number
    allBids.sort((a, b) => a.atBlock - b.atBlock);

    for (const bid of allBids) {
      await this.executeBid(bid);
    }
  }

  collectAllBids(interactionData, timeBase) {
    const bids = [];

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
      });
    }

    return bids;
  }

  async executeBid(bid) {
    // Advance to the target block
    await network.provider.send('hardhat_mine', [bid.atBlock.toString()]);

    const amount = await this.calculateAmount(bid.amount);
    const price = await this.calculatePrice(bid.price);

    try {
      const tx = await this.auction.submitBid(
        price,
        bid.amount.side === 'input',
        amount,
        bid.bidder,
        0, // prevTickPrice
        bid.hookData || '0x'
      );

      await tx.wait();
    } catch (error) {
      if (bid.expectRevert) {
        // Expected revert - this is fine
        return;
      }
      throw error;
    }
  }

  async calculateAmount(amountConfig) {
    // Implementation depends on amount type (raw, percentOfSupply, etc.)
    // This is a simplified version
    if (amountConfig.type === 'raw') {
      return BigInt(amountConfig.value);
    }
    // Add other amount calculation logic here
    return BigInt(amountConfig.value);
  }

  async calculatePrice(priceConfig) {
    if (priceConfig.type === 'tick') {
      // Convert tick to actual price
      return BigInt(priceConfig.value);
    }
    return BigInt(priceConfig.value);
  }

  async executeActions(interactionData, timeBase) {
    if (!interactionData.actions) return;

    for (const action of interactionData.actions) {
      if (action.type === 'Transfer') {
        await this.executeTransfers(action.interactions);
      } else if (action.type === 'AdminAction') {
        await this.executeAdminActions(action.interactions);
      }
    }
  }

  async executeTransfers(transferInteractions) {
    for (const interactionGroup of transferInteractions) {
      for (const interaction of interactionGroup) {
        await network.provider.send('hardhat_mine', [interaction.atBlock.toString()]);
        
        const { from, to, token, amount } = interaction.value;
        const toAddress = this.labelMap.get(to) || to;
        const amountValue = await this.calculateAmount(amount);

        // Execute the transfer
        // Implementation depends on token type (ERC20 vs ETH)
      }
    }
  }

  async executeAdminActions(adminInteractions) {
    for (const interactionGroup of adminInteractions) {
      for (const interaction of interactionGroup) {
        await network.provider.send('hardhat_mine', [interaction.atBlock.toString()]);
        
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

module.exports = BidSimulator;
