import {
  TestInteractionData,
  Group,
  BidData,
  Side,
  AmountType,
  PriceType,
  AdminActionMethod,
  AmountConfig,
  PriceConfig,
} from "../schemas/TestInteractionSchema";
import { Contract, ContractTransaction } from "ethers";
import {
  PERMIT2_ADDRESS,
  MAX_UINT256,
  ZERO_ADDRESS,
  UINT_160_MAX,
  UINT_48_MAX,
  LOG_PREFIXES,
  ERROR_MESSAGES,
} from "./constants";
import { IAllowanceTransfer } from "../../../typechain-types/test/e2e/artifacts/permit2/src/interfaces/IAllowanceTransfer";
import { TransactionInfo } from "./types";
import { TransferAction } from "../schemas/TestInteractionSchema";
import hre from "hardhat";

export enum BiddersType {
  NAMED = "named",
  GROUP = "group",
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
  private auctionDeployer: any; // Add reference to auction deployer for token resolution

  constructor(auction: Contract, currency: Contract, auctionDeployer?: any) {
    this.auction = auction;
    this.currency = currency;
    this.auctionDeployer = auctionDeployer;
  }

  async resolveTokenAddress(tokenIdentifier: string): Promise<string> {
    if (tokenIdentifier.startsWith("0x")) {
      return tokenIdentifier; // It's already an address
    }
    // Look up by name in the deployed tokens (from AuctionDeployer)
    if (this.auctionDeployer) {
      const tokenContract = this.auctionDeployer.getTokenByName(tokenIdentifier);
      if (tokenContract) {
        return await tokenContract.getAddress();
      }
    }
    throw new Error(ERROR_MESSAGES.TOKEN_IDENTIFIER_NOT_FOUND(tokenIdentifier));
  }

  async setupLabels(interactionData: TestInteractionData): Promise<void> {
    // Map symbolic labels to actual addresses
    this.labelMap.set("Auction", await this.auction.getAddress());

    // Add named bidders
    if (interactionData.namedBidders) {
      interactionData.namedBidders.forEach((bidder) => {
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
      interactionData.namedBidders.forEach((bidder) => {
        bidder.bids.forEach((bid) => {
          const internalBid = {
            bidData: bid,
            bidder: bidder.address,
            type: BiddersType.NAMED,
          };
          bids.push(internalBid);
        });

        // Implement recurring bids support
        bidder.recurringBids.forEach((recurringBid) => {
          for (let i = 0; i < recurringBid.occurrences; i++) {
            const blockNumber = recurringBid.startBlock + i * recurringBid.intervalBlocks;

            // Apply growth factors to amount and price
            let adjustedAmount = recurringBid.amount;
            let adjustedPrice = recurringBid.price;

            if (recurringBid.amountFactor && i > 0) {
              const factor = Math.pow(recurringBid.amountFactor, i);
              // Use BigInt arithmetic to avoid scientific notation conversion
              const originalValue = BigInt(recurringBid.amount.value.toString());
              const factorScaled = Math.floor(factor * 1000000); // Scale factor to avoid decimals
              const adjustedValue = (originalValue * BigInt(factorScaled)) / BigInt(1000000);
              adjustedAmount = {
                ...recurringBid.amount,
                value: adjustedValue.toString(),
              };
            }

            if (recurringBid.priceFactor && i > 0) {
              const factor = Math.pow(recurringBid.priceFactor, i);
              // Use BigInt arithmetic to avoid scientific notation conversion
              const originalValue = BigInt(recurringBid.price.value.toString());
              const factorScaled = Math.floor(factor * 1000000); // Scale factor to avoid decimals
              const adjustedValue = (originalValue * BigInt(factorScaled)) / BigInt(1000000);
              adjustedPrice = {
                ...recurringBid.price,
                value: adjustedValue.toString(),
              };
            }

            const internalBid: InternalBidData = {
              bidder: bidder.address,
              type: BiddersType.NAMED,
              bidData: {
                atBlock: blockNumber,
                amount: adjustedAmount,
                price: adjustedPrice,
                previousTick: (recurringBid.previousTick || 0) + (recurringBid.previousTickIncrement || 0) * i,
                hookData: recurringBid.hookData,
                expectRevert: undefined,
              },
            };
            bids.push(internalBid);
          }
        });
      });
    }

    // Group bidders
    if (interactionData.groups) {
      interactionData.groups.forEach((group) => {
        const bidders = this.groupBidders.get(group.labelPrefix);
        if (bidders) {
          for (let round = 0; round < group.rounds; round++) {
            for (let i = 0; i < group.count; i++) {
              const bidder = bidders[i];
              const atBlock =
                group.startBlock +
                round * (group.rotationIntervalBlocks + group.betweenRoundsBlocks) +
                i * group.rotationIntervalBlocks;

              bids.push({
                bidData: {
                  atBlock: atBlock,
                  amount: group.amount,
                  price: group.price,
                  hookData: group.hookData,
                  previousTick: group.previousTick,
                },
                bidder,
                type: BiddersType.GROUP,
                group: group.labelPrefix,
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
      price,
    );

    if (this.currency) {
      await this.grantPermit2Allowances(this.currency, bidder, transactionInfos);
    }
    let tx: ContractTransaction; // Transaction response type varies
    let msg: string;
    if (this.currency) {
      msg = `   🔍 Bidding with ERC20 currency: ${await this.currency.getAddress()}`;
      tx = await this.auction
        .getFunction("submitBid")
        .populateTransaction(
          price,
          bidData.amount.side === Side.INPUT,
          amount,
          bidder,
          previousTickPrice,
          bidData.hookData || "0x",
        );
    } else {
      // For ETH currency, send the required amount as msg.value
      msg = `   🔍 Bidding with Native currency`;
      tx = await this.auction
        .getFunction("submitBid")
        .populateTransaction(
          price,
          bidData.amount.side === Side.INPUT,
          amount,
          bidder,
          previousTickPrice,
          bidData.hookData || "0x",
          { value: requiredCurrencyAmount },
        );
    }
    transactionInfos.push({ tx, from: bidder, msg, expectRevert: bidData.expectRevert });
  }

  async validateExpectedRevert(error: unknown, expectedRevert: string): Promise<void> {
    // Extract the revert data string from the error
    const errorObj = error as any;
    let actualRevertData = errorObj?.data || errorObj?.error?.data || errorObj?.info?.data || "";

    // Try to decode the revert reason from the data
    if (actualRevertData && actualRevertData.startsWith("0x")) {
      try {
        // Remove the 0x prefix and decode the hex string
        const hexData = actualRevertData.slice(2);

        // Check if it's a standard revert with reason (function selector 0x08c379a0)
        if (hexData.startsWith("08c379a0")) {
          // Skip the function selector (8 bytes) and decode the string
          const reasonHex = hexData.slice(8);
          const reasonBytes = Buffer.from(reasonHex, "hex");
          const decodedReason = reasonBytes.toString("utf8").replace(/\0/g, "").trim();

          if (!actualRevertData.includes(expectedRevert) && decodedReason) {
            actualRevertData = decodedReason;
          }
        }
      } catch (decodeError) {
        // If decoding fails, use the raw data
        console.log(LOG_PREFIXES.INFO, "Could not decode revert reason, using raw data");
      }
    }

    // Check if the revert data contains the expected string
    if (!actualRevertData.includes(expectedRevert)) {
      throw new Error(ERROR_MESSAGES.EXPECTED_REVERT_NOT_FOUND(expectedRevert, actualRevertData));
    }
    console.log(LOG_PREFIXES.SUCCESS, "Expected revert validated:", expectedRevert);
  }

  async calculateAmount(amountConfig: AmountConfig): Promise<bigint> {
    // Implementation depends on amount type (raw, percentOfSupply, etc.)
    let value: bigint = 0n;
    if (amountConfig.type === AmountType.RAW) {
      // Ensure the value is treated as a string to avoid scientific notation conversion
      value = BigInt(amountConfig.value.toString());
    }

    if (amountConfig.type === AmountType.PERCENT_OF_SUPPLY) {
      // PERCENT_OF_SUPPLY can only be used for auctioned token (output), not currency (input)
      if (amountConfig.side === Side.INPUT) {
        throw new Error(ERROR_MESSAGES.PERCENT_OF_SUPPLY_INVALID_SIDE);
      }

      // Calculate percentage of total token supply
      // Get the total supply from the auction contract
      const totalSupply = await this.auction.totalSupply();
      console.log(LOG_PREFIXES.INFO, "Total supply from auction:", totalSupply.toString());

      // Parse decimal percentage (e.g., "5.5" = 5.5%)
      const percentageValue = parseFloat(amountConfig.value);
      const percentage = BigInt(Math.floor(percentageValue * 100)); // Convert to basis points (5.5% = 550 basis points)
      value = (totalSupply * percentage) / 10000n;
    }

    if (amountConfig.variation) {
      const variation = BigInt(amountConfig.variation.toString());
      const randomVariation = Math.floor(Math.random() * (2 * Number(variation) + 1)) - Number(variation);
      value = value + BigInt(randomVariation);
      if (value < 0n) value = 0n;
    }

    return value;
  }

  async calculatePrice(priceConfig: PriceConfig): Promise<bigint> {
    let value: bigint;

    if (priceConfig.type === PriceType.TICK) {
      // Convert tick to actual price using the same logic as the Foundry tests
      value = this.tickNumberToPriceX96(parseInt(priceConfig.value.toString()));
    } else {
      // Ensure the value is treated as a string to avoid scientific notation conversion
      value = BigInt(priceConfig.value.toString());
    }

    // Implement price variation
    if (priceConfig.variation) {
      const variationPercent = parseFloat(priceConfig.variation);
      const variationAmount = (Number(value) * variationPercent) / 100;
      const randomVariation = (Math.random() - 0.5) * 2 * variationAmount; // -variation to +variation
      const adjustedValue = Number(value) + randomVariation;

      // Ensure the price doesn't go negative
      value = BigInt(Math.max(0, Math.floor(adjustedValue)));
    }

    return value;
  }

  tickNumberToPriceX96(tickNumber: number): bigint {
    // This mirrors the logic from AuctionBaseTest.sol
    const FLOOR_PRICE = 1000n * 2n ** 96n; // 1000 * 2^96
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

  async executeTransfers(transferInteractions: TransferAction[], transactionInfos: TransactionInfo[]): Promise<void> {
    // This handles token transfers between addresses
    // Support for both ERC20 tokens and native currency
    // Resolves label references for 'to' addresses
    for (const interaction of transferInteractions) {
      const { from, to, token, amount } = interaction.value;
      const toAddress = this.labelMap.get(to) || to;
      const amountValue = BigInt(amount.toString()); // Transfer actions use raw amounts directly

      // Execute the transfer based on token type
      if (token === ZERO_ADDRESS) {
        // Native ETH transfer
        await this.executeNativeTransfer(
          from,
          toAddress,
          amountValue,
          interaction.value.expectRevert || "",
          transactionInfos,
        );
      } else {
        // ERC20 token transfer - resolve token address first
        const resolvedTokenAddress = await this.resolveTokenAddress(token);
        await this.executeTokenTransfer(
          from,
          toAddress,
          resolvedTokenAddress,
          amountValue,
          interaction.value.expectRevert || "",
          transactionInfos,
        );
      }
    }
  }

  private async executeNativeTransfer(
    from: string,
    to: string,
    amount: bigint,
    expectRevert: string,
    transactionInfos: TransactionInfo[],
  ): Promise<void> {
    // Send native ETH
    const tx = {
      to,
      value: amount,
    };
    let msg = `   ✅ Native transfer: ${(parseFloat(amount.toString()) / 10 ** 18).toString()} ETH`;
    transactionInfos.push({ tx, from, msg, expectRevert });
  }

  private async executeTokenTransfer(
    from: string,
    to: string,
    tokenAddress: string,
    amount: bigint,
    expectRevert: string,
    transactionInfos: TransactionInfo[],
  ): Promise<void> {
    // Get the token contract
    const token = await hre.ethers.getContractAt("ERC20", tokenAddress);
    let decimals = await token.decimals();
    let symbol = await token.symbol();
    // Execute the transfer
    const tx = await token.getFunction("transfer").populateTransaction(to, amount);
    let msg = `   ✅ Token transfer: ${(parseFloat(amount.toString()) / 10 ** Number(decimals)).toString()} ${symbol}`;
    transactionInfos.push({ tx, from, msg, expectRevert });
  }

  async executeAdminActions(adminInteractions: any[], transactionInfos: TransactionInfo[]): Promise<void> {
    for (const interactionGroup of adminInteractions) {
      for (const interaction of interactionGroup) {
        const { kind } = interaction.value;
        if (kind === AdminActionMethod.SWEEP_CURRENCY) {
          let tx = await this.auction.getFunction("sweepCurrency").populateTransaction();
          let msg = `   ✅ Sweeping currency`;
          transactionInfos.push({ tx, from: null, msg });
        } else if (kind === AdminActionMethod.SWEEP_UNSOLD_TOKENS) {
          let tx = await this.auction.getFunction("sweepUnsoldTokens").populateTransaction();
          let msg = `   ✅ Sweeping unsold tokens`;
          transactionInfos.push({ tx, from: null, msg });
        }
      }
    }
  }

  async grantPermit2Allowances(currency: Contract, bidder: string, transactionInfos: TransactionInfo[]): Promise<void> {
    // First, approve Permit2 to spend the tokens
    const approveTx = await currency.getFunction("approve").populateTransaction(PERMIT2_ADDRESS, MAX_UINT256);
    let approveMsg = `   ✅ Approving Permit2 to spend tokens`;
    transactionInfos.push({ tx: approveTx, from: bidder, msg: approveMsg });

    // Then, call Permit2's approve function to grant allowance to the auction contract
    const permit2 = (await hre.ethers.getContractAt(
      "IAllowanceTransfer",
      PERMIT2_ADDRESS,
    )) as unknown as IAllowanceTransfer;
    const auctionAddress = await this.auction.getAddress();
    const maxAmount = UINT_160_MAX; // uint160 max
    const maxExpiration = UINT_48_MAX; // uint48 max (far in the future)
    let tx = await permit2.getFunction("approve").populateTransaction(
      await currency.getAddress(), // token address
      auctionAddress, // spender (auction contract)
      maxAmount, // amount (max uint160)
      maxExpiration, // expiration (max uint48)
    );
    let msg = `   ✅ Granting Permit2 allowance to the auction contract`;
    transactionInfos.push({ tx, from: bidder, msg });
  }
}
