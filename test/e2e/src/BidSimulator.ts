import { ActionType, TestInteractionData, Group, BidData, Side, AmountType, PriceType, AdminActionMethod, Address, AmountConfig, PriceConfig } from '../schemas/TestInteractionSchema';
import { Contract, ContractTransaction } from "ethers";
import hre from "hardhat";
import { PERMIT2_ADDRESS, MAX_UINT256, ZERO_ADDRESS, UINT_160_MAX, UINT_48_MAX } from './constants';
import { IAllowanceTransfer } from '../../../typechain-types/test/e2e/artifacts/permit2/src/interfaces/IAllowanceTransfer';
import { Signer } from 'ethers';
import { TransactionInfo } from './types';

export enum BiddersType {
  NAMED = 'named',
  GROUP = 'group'
}

export interface InternalBidData {
  bidData: BidData;
  bidder: string;
  type: BiddersType;
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

  public collectAllBids(interactionData: TestInteractionData): InternalBidData[] {
    const bids: InternalBidData[] = [];

    // Named bidders
    if (interactionData.namedBidders) {
      interactionData.namedBidders.forEach(bidder => {
        bidder.bids.forEach(bid => {
          const internalBid = {
            bidData: bid,
            bidder: bidder.address,
            type: BiddersType.NAMED,
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
              const atBlock = group.startBlock + 
                (round * (group.rotationIntervalBlocks + group.betweenRoundsBlocks)) +
                (i * group.rotationIntervalBlocks);
              
              bids.push({
                bidData: {
                  atBlock: atBlock,
                  amount: group.amount,
                  price: group.price,
                  hookData: group.hookData,
                  previousTick: group.previousTick
                },
                bidder,
                type: BiddersType.GROUP,
                group: group.labelPrefix
              });
            }
          }
        }
      });
    }

    return bids;
  }

  async executeBid(bid: InternalBidData, transactionInfos: TransactionInfo[]): Promise<void> {
    // This method just executes the bid transaction

    const bidData = bid.bidData;
    const bidder = bid.bidder;

    // For the first bid, use tick 1 as prevTickPrice (floor price)
    // For subsequent bids, we use the previous tick
    let previousTickPrice: bigint = this.tickNumberToPriceX96(bidData.previousTick);
    
    const amount = await this.calculateAmount(bidData.amount);
    const price = await this.calculatePrice(bidData.price);

    // Calculate required currency amount for the bid
    const requiredCurrencyAmount = await this.calculateRequiredCurrencyAmount(
      bidData.amount.side === Side.INPUT,
      amount,
      price
    );

        if (this.currency) {
          await this.grantPermit2Allowances(this.currency, bidder, transactionInfos);
        }
        let tx: ContractTransaction; // Transaction response type varies
        let msg: string; 
      if (this.currency) {
        msg = `   🔍 Using ERC20 currency: ${await this.currency.getAddress()}`;
        tx = await this.auction.getFunction('submitBid').populateTransaction(
          price,
          bidData.amount.side === Side.INPUT,
          amount,
          bidder,
          previousTickPrice,
          bidData.hookData || '0x'
        );
        
      } else {
        // For ETH currency, send the required amount as msg.value
        msg = `   🔍 Using Native currency`;
        tx = await this.auction.getFunction('submitBid').populateTransaction(
          price,
          bidData.amount.side === Side.INPUT,
          amount,
          bidder,
          previousTickPrice,
          bidData.hookData || '0x',
          { value: requiredCurrencyAmount }
        );
      }
      transactionInfos.push({ tx, from: bidder, msg, expectRevert: bidData.expectRevert });
  }

  async validateExpectedRevert(error: unknown, expectedRevert: string): Promise<void> {
    // TODO: decode reason from revert data
    // Extract the revert data string from the error
    const errorObj = error as any;
    const actualRevertData = errorObj?.data || errorObj?.error?.data || errorObj?.info?.data || '';
    
    // Check if the revert data contains the expected string
    if (!actualRevertData.includes(expectedRevert)) {
      throw new Error(`Expected revert data to contain "${expectedRevert}", but got: ${actualRevertData}`);
    }
    console.log(`   ✅ Expected revert validated: ${expectedRevert}`);
  }

  async calculateAmount(amountConfig: AmountConfig): Promise<bigint> {
    // Implementation depends on amount type (raw, percentOfSupply, etc.)
    // This is a simplified version
    if (amountConfig.type === AmountType.RAW) {
      return BigInt(amountConfig.value);
    }
    
    if (amountConfig.type === AmountType.PERCENT_OF_SUPPLY) {
      // PERCENT_OF_SUPPLY can only be used for auctioned token (output), not currency (input)
      if (amountConfig.side === Side.INPUT) {
        throw new Error('PERCENT_OF_SUPPLY can only be used for auctioned token (OUTPUT), not currency (INPUT)');
      }
      
      // Calculate percentage of total token supply
      // Get the total supply from the auction contract
      const totalSupply = await this.auction.totalSupply();
      console.log(`   🔍 Total supply from auction: ${totalSupply.toString()}`);
      
      // Parse decimal percentage (e.g., "5.5" = 5.5%)
      const percentageValue = parseFloat(amountConfig.value);
      const percentage = BigInt(Math.floor(percentageValue * 100)); // Convert to basis points (5.5% = 550 basis points)
      return (totalSupply * percentage) / 10000n;
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

  async calculatePrice(priceConfig: PriceConfig): Promise<bigint> {
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

  async executeActions(interactionData: TestInteractionData, transactionInfos: TransactionInfo[]): Promise<void> {
    if (!interactionData.actions) return;

    for (const action of interactionData.actions) {
      if (action.type === ActionType.TRANSFER_ACTION) {
        await this.executeTransfers(action.interactions, transactionInfos);
      } else if (action.type === ActionType.ADMIN_ACTION) {
        await this.executeAdminActions(action.interactions, transactionInfos);
      }
    }
  }

  async executeTransfers(transferInteractions: any[], transactionInfos: TransactionInfo[]): Promise<void> {
    // This handles token transfers between addresses
    // Support for both ERC20 tokens and native currency
    // Resolves label references for 'to' addresses
    for (const interactionGroup of transferInteractions) {
      for (const interaction of interactionGroup) {
        const { from, to, token, amount } = interaction.value;
        const toAddress = this.labelMap.get(to) || to;
        const amountValue = BigInt(amount); // Transfer actions use raw amounts directly

        // Execute the transfer based on token type
        if (token === ZERO_ADDRESS) {
          // Native ETH transfer
          await this.executeNativeTransfer(from, toAddress, amountValue, transactionInfos);
        } else {
          // ERC20 token transfer
          await this.executeTokenTransfer(from, toAddress, token, amountValue, transactionInfos);
        }
      }
    }
  }

  private async executeNativeTransfer(from: string, to: string, amount: bigint, transactionInfos: TransactionInfo[]): Promise<void> {
      // Send native ETH
      const tx = {
        to,
        value: amount
      };
      let msg = `   ✅ Native transfer: ${amount.toString()} ETH`;
      transactionInfos.push({ tx, from, msg });
  }
  
  private async executeTokenTransfer(from: string, to: string, tokenAddress: string, amount: bigint, transactionInfos: TransactionInfo[]): Promise<void> {
    // Get the token contract
    const token = await hre.ethers.getContractAt('IERC20Minimal', tokenAddress);
    
      // Execute the transfer
      const tx = await token.getFunction('transfer').populateTransaction(to, amount);
      let msg = `   ✅ Token transfer: ${amount.toString()} tokens`;
      transactionInfos.push({ tx, from, msg });
  }

  async executeAdminActions(adminInteractions: any[], transactionInfos: TransactionInfo[]): Promise<void> {
    for (const interactionGroup of adminInteractions) {
      for (const interaction of interactionGroup) {
        const { kind } = interaction.value;
        if (kind === AdminActionMethod.SWEEP_CURRENCY) {
          let tx = await this.auction.getFunction('sweepCurrency').populateTransaction();
          let msg = `   ✅ Sweeping currency`;
          transactionInfos.push({ tx, from: null, msg });
        } else if (kind === AdminActionMethod.SWEEP_UNSOLD_TOKENS) {
          let tx = await this.auction.getFunction('sweepUnsoldTokens').populateTransaction();
          let msg = `   ✅ Sweeping unsold tokens`;
          transactionInfos.push({ tx, from: null, msg });
        } 
      }
    }
  }

  async grantPermit2Allowances(currency: Contract, bidder: string, transactionInfos: TransactionInfo[]): Promise<void> {
    // First, approve Permit2 to spend the tokens
    const approveTx = await currency.getFunction('approve').populateTransaction(PERMIT2_ADDRESS, MAX_UINT256);
    let approveMsg = `   ✅ Approving Permit2 to spend tokens`;
    transactionInfos.push({ tx: approveTx, from: bidder, msg: approveMsg });

    // Then, call Permit2's approve function to grant allowance to the auction contract
    const permit2 = await hre.ethers.getContractAt('IAllowanceTransfer', PERMIT2_ADDRESS) as unknown as IAllowanceTransfer;
    const auctionAddress = await this.auction.getAddress();
    const maxAmount = UINT_160_MAX; // uint160 max
    const maxExpiration = UINT_48_MAX; // uint48 max (far in the future)
    let tx = await permit2.getFunction('approve').populateTransaction(
      await currency.getAddress(), // token address
      auctionAddress,              // spender (auction contract)
      maxAmount,                   // amount (max uint160)
      maxExpiration                // expiration (max uint48)
    );
    let msg = `   ✅ Granting Permit2 allowance to the auction contract`;
    transactionInfos.push({ tx, from: bidder, msg });
  }

}
