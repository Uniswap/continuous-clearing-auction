import { TestInteractionData, Group, BidData, AdminActionMethod, AmountConfig } from "../schemas/TestInteractionSchema";
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
import { TransferAction, AdminAction } from "../schemas/TestInteractionSchema";
import { calculatePrice, resolveTokenAddress, tickNumberToPriceX96 } from "./utils";
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

  /**
   * Sets up label mappings for symbolic addresses and group bidders.
   * @param interactionData - Test interaction data containing named bidders and groups
   */
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

  /**
   * Generates group bidders and maps them to their group names.
   * @param groups - Array of group configurations
   */
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

  /**
   * Collects all bids from named bidders and groups.
   * @param interactionData - Test interaction data containing bidders and groups
   * @returns Array of internal bid data for execution
   */
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
              const factor = recurringBid.priceFactor * i;
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
                hookData: recurringBid.hookData,
                expectRevert: undefined,
              },
            };
            if (recurringBid.previousTick) {
              internalBid.bidData.previousTick =
                recurringBid.previousTick + (recurringBid.previousTickIncrement || 0) * i;
            }
            if (recurringBid.prevTickPrice) {
              // Handle prevTickPriceIncrement as number or string (for huge values)
              const basePrevTickPrice = BigInt(recurringBid.prevTickPrice);
              const increment = recurringBid.prevTickPriceIncrement
                ? typeof recurringBid.prevTickPriceIncrement === "string"
                  ? BigInt(recurringBid.prevTickPriceIncrement)
                  : BigInt(recurringBid.prevTickPriceIncrement)
                : 0n;
              internalBid.bidData.prevTickPrice = (basePrevTickPrice + increment * BigInt(i)).toString();
            }
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

  /**
   * Executes a single bid by creating and submitting the transaction.
   * @param bid - Internal bid data containing bidder, bid data, and type
   * @param transactionInfos - Array to collect transaction information
   * @throws Error if bid execution fails or expected revert validation fails
   */
  async executeBid(bid: InternalBidData, transactionInfos: TransactionInfo[]): Promise<void> {
    // This method just executes the bid transaction

    const bidData = bid.bidData;
    const bidder = bid.bidder;

    // Calculate from tick number
    const floorPrice = await this.auction.floorPrice();
    const tickSpacing = await this.auction.tickSpacing();
    // Use prevTickPrice if provided, otherwise calculate from previousTick
    let previousTickPrice: bigint;
    if (bidData.prevTickPrice) {
      // Direct price hint provided
      previousTickPrice = BigInt(bidData.prevTickPrice);
    } else if (bidData.previousTick) {
      previousTickPrice = tickNumberToPriceX96(bidData.previousTick, floorPrice, tickSpacing);
    } else {
      throw new Error("previousTick or prevTickPrice must be provided");
    }

    const amount = await this.calculateAmount(bidData.amount);
    const price = await calculatePrice(bidData.price, floorPrice, tickSpacing);

    if (this.currency) {
      await this.grantPermit2Allowances(this.currency, bidder, transactionInfos);
    }
    let tx: ContractTransaction; // Transaction response type varies
    let msg: string;
    if (this.currency) {
      msg = `   Bidding with ERC20 currency: ${await this.currency.getAddress()}`;
      tx = await this.auction
        .getFunction("submitBid(uint256,uint128,address,uint256,bytes)")
        .populateTransaction(price, amount, bidder, previousTickPrice, bidData.hookData || "0x");
    } else {
      // For native currency, send the required amount as msg.value
      msg = `   Bidding with Native currency`;
      tx = await this.auction
        .getFunction("submitBid(uint256,uint128,address,uint256,bytes)")
        .populateTransaction(price, amount, bidder, previousTickPrice, bidData.hookData || "0x", { value: amount });
    }
    transactionInfos.push({ tx, from: bidder, msg, expectRevert: bidData.expectRevert });
  }

  /**
   * Validates that a transaction reverted with the expected error message.
   * @param error - The error object from the failed transaction
   * @param expectedRevert - The expected revert message to match
   * @throws Error if the revert message doesn't match the expected value
   */
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

  /**
   * Parse variation string into an absolute amount.
   * Supports both percentage format (e.g., "10%") and raw amount format.
   * @param variation - Variation string in percentage or raw amount format
   * @param baseValue - The base value to apply percentage to
   * @returns Variation amount as a bigint
   */
  private parseVariation(variation: string, baseValue: bigint): bigint {
    if (variation.endsWith("%")) {
      // Percentage: convert to ratio and apply to base value (e.g., "10%" of 1 ETH -> 0.1 ETH)
      const percentage = parseFloat(variation.slice(0, -1));
      const ratio = percentage / 100;
      const variationAmount = (baseValue * BigInt(Math.floor(ratio * 1000000))) / 1000000n;
      return variationAmount;
    } else {
      // Raw amount: use as-is
      return BigInt(variation.toString());
    }
  }

  /**
   * Calculates the actual bid amount based on the amount configuration.
   * @param amountConfig - Amount configuration specifying type, side, value, and optional variance
   * @returns The calculated amount as a bigint
   * @throws Error if amount type is unsupported or PERCENT_OF_SUPPLY is used incorrectly
   */
  async calculateAmount(amountConfig: AmountConfig): Promise<bigint> {
    // Ensure the value is treated as a string to avoid scientific notation conversion
    let value: bigint = BigInt(amountConfig.value.toString());

    if (amountConfig.variation) {
      const variation = this.parseVariation(amountConfig.variation.toString(), value);
      const randomVariation = Math.floor(Math.random() * (2 * Number(variation) + 1)) - Number(variation);
      value = value + BigInt(randomVariation);
      if (value < 0n) value = 0n;
    }

    return value;
  }

  /**
   * Executes token transfer actions.
   * @param transferInteractions - Array of transfer actions to execute
   * @param transactionInfos - Array to collect transaction information
   */
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
        const resolvedTokenAddress = await resolveTokenAddress(token, this.auctionDeployer);
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

  /**
   * Executes a native ETH transfer between addresses.
   * @param from - The sender address
   * @param to - The recipient address
   * @param amount - The amount to transfer in wei
   * @param expectRevert - Expected revert message if the transfer should fail
   * @param transactionInfos - Array to collect transaction information
   */
  private async executeNativeTransfer(
    from: string,
    to: string,
    amount: bigint,
    expectRevert: string,
    transactionInfos: TransactionInfo[],
  ): Promise<void> {
    // Send native currency
    const tx = {
      to,
      value: amount,
    };
    let msg = `   Native transfer: ${(parseFloat(amount.toString()) / 10 ** 18).toString()} ETH`;
    transactionInfos.push({ tx, from, msg, expectRevert });
  }

  /**
   * Executes a token transfer between addresses.
   * @param from - The sender address
   * @param to - The recipient address
   * @param tokenAddress - The token contract address
   * @param amount - The amount to transfer
   * @param expectRevert - Expected revert message if the transfer should fail
   * @param transactionInfos - Array to collect transaction information
   */
  async executeTokenTransfer(
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
    let msg = `   Token transfer: ${(parseFloat(amount.toString()) / 10 ** Number(decimals)).toString()} ${symbol}`;
    transactionInfos.push({ tx, from, msg, expectRevert });
  }

  /**
   * Executes admin actions on the auction contract.
   * @param adminInteractions - Array of admin action groups to execute
   * @param transactionInfos - Array to collect transaction information
   */
  async executeAdminActions(adminInteractions: AdminAction[], transactionInfos: TransactionInfo[]): Promise<void> {
    console.log(LOG_PREFIXES.INFO, "Executing admin actions:", adminInteractions);
    for (const interaction of adminInteractions) {
      if (interaction.method === AdminActionMethod.CHECKPOINT) {
        let tx = await this.auction.getFunction("checkpoint").populateTransaction();
        let msg = `   Creating checkpoint`;
        transactionInfos.push({ tx, from: null, msg });
      } else if (interaction.method === AdminActionMethod.SWEEP_CURRENCY) {
        let tx = await this.auction.getFunction("sweepCurrency").populateTransaction();
        let msg = `   Sweeping currency`;
        transactionInfos.push({ tx, from: null, msg });
      } else if (interaction.method === AdminActionMethod.SWEEP_UNSOLD_TOKENS) {
        let tx = await this.auction.getFunction("sweepUnsoldTokens").populateTransaction();
        let msg = `   Sweeping unsold tokens`;
        transactionInfos.push({ tx, from: null, msg });
      }
    }
  }

  /**
   * Grants Permit2 allowances for a bidder to interact with the auction.
   * @param currency - The currency contract to grant allowance for
   * @param bidder - The bidder address to grant allowance to
   * @param transactionInfos - Array to collect transaction information
   */
  async grantPermit2Allowances(currency: Contract, bidder: string, transactionInfos: TransactionInfo[]): Promise<void> {
    // First, approve Permit2 to spend the tokens
    const approveTx = await currency.getFunction("approve").populateTransaction(PERMIT2_ADDRESS, MAX_UINT256);
    let approveMsg = `   Approving Permit2 to spend tokens`;
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
    let msg = `   Granting Permit2 allowance to the auction contract`;
    transactionInfos.push({ tx, from: bidder, msg });
  }
}
