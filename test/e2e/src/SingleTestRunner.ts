import { SchemaValidator } from "./SchemaValidator";
import { Address, TestSetupData } from "../schemas/TestSetupSchema";
import {
  ActionType,
  TestInteractionData,
  AdminAction,
  TransferAction,
  AssertionInfo,
} from "../schemas/TestInteractionSchema";
import { AuctionDeployer } from "./AuctionDeployer";
import { BidSimulator, InternalBidData } from "./BidSimulator";
import { AssertionEngine, AuctionState } from "./AssertionEngine";
import { Contract, Interface } from "ethers";
import { Network } from "hardhat/types";
import {
  PERMIT2_ADDRESS,
  LOG_PREFIXES,
  ERROR_MESSAGES,
  METHODS,
  TYPES,
  PENDING_STATE,
  EVENTS,
  ZERO_ADDRESS,
  NATIVE_CURRENCY_NAME,
} from "./constants";
import { artifacts } from "hardhat";
import { EventData, HashWithRevert, TransactionInfo, EventType, ActionData, TokenContract } from "./types";
import { TransactionRequest } from "ethers";
import { parseBoolean } from "./utils";
import { GroupConfig } from "../schemas/TestSetupSchema";
import hre from "hardhat";

export interface TestResult {
  setupData: TestSetupData;
  interactionData: TestInteractionData;
  auction: Contract;
  auctionedToken: Address | null;
  currencyToken: Address | null;
  finalState: AuctionState;
  success: boolean;
}

interface BidInfo {
  bidId: number;
  owner: string;
  maxPrice: bigint;
  amount: bigint;
}

interface CheckpointInfo {
  blockNumber: number;
  clearingPrice: bigint;
}

export class SingleTestRunner {
  private network: Network;
  private schemaValidator: SchemaValidator;
  private deployer: AuctionDeployer;
  private cachedInterface: Interface | null = null;
  private bidsByOwner: Map<string, BidInfo[]> = new Map(); // Track bid info per owner
  private startBalancesMap: Map<Address, Map<Address, bigint>> = new Map(); // Track start balances for each owner
  private checkpoints: CheckpointInfo[] = []; // Track all checkpoints
  private auction: Contract | null = null; // Store auction for bid tracking

  constructor() {
    this.network = hre.network;
    this.schemaValidator = new SchemaValidator();
    this.deployer = new AuctionDeployer();
  }

  /**
   * Runs a complete E2E test from setup to completion.
   * @param setupData - Test setup data containing auction parameters and environment
   * @param interactionData - Test interaction data containing bids, actions, and assertions
   * @returns Test result containing success status and any errors
   * @throws Error if test setup fails or current block is past auction start block
   */
  async runFullTest(setupData: TestSetupData, interactionData: TestInteractionData): Promise<TestResult> {
    console.log(LOG_PREFIXES.TEST, "Running test:", setupData.name, "+", interactionData.name);

    console.log(LOG_PREFIXES.SUCCESS, "Schema validation passed");

    // Clear instance state from previous tests
    this.bidsByOwner.clear();
    this.checkpoints = [];
    this.auction = null;
    this.cachedInterface = null;

    // Reset the Hardhat network to start fresh for each test
    // Deploy Permit2 at canonical address (one-time setup)
    await this.resetChainWithPermit2();
    console.log(LOG_PREFIXES.INFO, "Reset Hardhat network to start fresh");

    // PHASE 1: Setup the auction environment
    console.log(LOG_PREFIXES.INFO, "Phase 1: Setting up auction environment...");

    // Check current block and auction start block
    const currentBlock = await hre.ethers.provider.getBlockNumber();
    const auctionStartBlock = parseInt(setupData.env.startBlock) + (setupData.env.offsetBlocks ?? 0);
    console.log(LOG_PREFIXES.CONFIG, "Current block:", currentBlock, ", Auction start block:", auctionStartBlock);

    if (currentBlock < auctionStartBlock) {
      const blocksToMine = auctionStartBlock - currentBlock;
      await hre.ethers.provider.send(METHODS.HARDHAT.MINE, [`0x${blocksToMine.toString(16)}`]);
      console.log(LOG_PREFIXES.INFO, "Mined", blocksToMine, "blocks to reach auction start block", auctionStartBlock);
    } else if (currentBlock > auctionStartBlock) {
      throw new Error(ERROR_MESSAGES.BLOCK_ALREADY_PAST_START(currentBlock, auctionStartBlock));
    }

    let setupTransactions: TransactionInfo[] = [];
    // Initialize deployer with tokens and factory (one-time setup)
    await this.deployer.initialize(setupData, setupTransactions);
    this.generateAddressesForGroups(setupData.env.groups ?? []);
    console.log(LOG_PREFIXES.INFO, "Generated addresses for groups: ", setupData.env.groups);
    // Setup balances
    await this.deployer.setupBalances(setupData, setupTransactions, this.startBalancesMap);
    await this.handleInitializeTransactions(setupTransactions);
    setupTransactions = [];
    // Create the auction
    const auction: Contract = await this.deployer.createAuction(setupData, setupTransactions);
    this.auction = auction; // Store for bid tracking

    console.log(LOG_PREFIXES.AUCTION, "Auction deployed:", await auction.getAddress());

    // PHASE 2: Execute interactions on the configured auction
    console.log(LOG_PREFIXES.PHASE, "Phase 2: Executing interaction scenario...");
    const auctionedToken = this.deployer.getTokenByName(setupData.auctionParameters.auctionedToken) ?? null;
    const currencyToken =
      setupData.auctionParameters.currency === "0x0000000000000000000000000000000000000000"
        ? null
        : this.deployer.getTokenByName(setupData.auctionParameters.currency) ?? null;
    const bidSimulator = new BidSimulator(auction, currencyToken as Contract, this.deployer);
    const assertionEngine = new AssertionEngine(auction, auctionedToken, currencyToken, this.deployer);

    // Setup labels and execute the interaction scenario
    await bidSimulator.setupLabels(interactionData, setupData);

    // Execute bids and actions with integrated checkpoint validation
    await this.executeWithAssertions(
      bidSimulator,
      assertionEngine,
      interactionData,
      setupTransactions,
      setupData.env.startBlock,
      setupData.env.offsetBlocks ?? 0,
    );

    console.log(LOG_PREFIXES.SUCCESS, "Bids executed and assertions validated successfully");

    // Get final state at the end of the auction
    const blockBeforeFinalState = await hre.ethers.provider.getBlockNumber();
    const auctionEndBlock =
      parseInt(setupData.env.startBlock) +
      setupData.auctionParameters.auctionDurationBlocks +
      (setupData.env.offsetBlocks ?? 0);

    // Mine to after the auction ends if needed to get accurate final state
    if (blockBeforeFinalState < auctionEndBlock) {
      const blocksToMine = auctionEndBlock - blockBeforeFinalState + 1;
      await hre.ethers.provider.send("hardhat_mine", [`0x${blocksToMine.toString(16)}`]);
    }

    // Get final state as-is (without forcing a checkpoint)
    const finalState = await assertionEngine.getAuctionState();

    // Don't add final state as a checkpoint - only use checkpoints from actual events
    // The contract only validates hints against stored checkpoints from CheckpointUpdated events
    let calculatedCurrencyRaised = -1;
    // Exit and claim all bids if auction graduated
    if (finalState.isGraduated) {
      calculatedCurrencyRaised = await this.exitAndClaimAllBids(
        auction,
        setupData,
        currencyToken,
        bidSimulator.getReverseLabelMap(),
      );
    }

    // Log balances for all funded accounts (after claiming)
    await this.logAccountBalances(setupData, this.deployer, auctionedToken);
    this.logFinalState(finalState);
    console.log(LOG_PREFIXES.FINAL, "Test completed successfully!");
    await this.logSummary(auction, currencyToken, auctionedToken, finalState, calculatedCurrencyRaised);
    return {
      setupData,
      interactionData,
      auction,
      auctionedToken: auctionedToken ? ((await auctionedToken.getAddress()) as Address) : null,
      currencyToken: currencyToken ? ((await currencyToken.getAddress()) as Address) : null,
      finalState,
      success: true,
    };
  }

  private async logSummary(
    auction: Contract,
    currencyToken: TokenContract | null,
    auctionedToken: TokenContract | null,
    finalState: AuctionState,
    totalCurrencyRaised: number,
  ): Promise<void> {
    let bidCount = 0;
    for (const [, bids] of this.bidsByOwner.entries()) {
      bidCount += bids.length;
    }
    const auctionDurationBlocks = (await auction.endBlock()) - (await auction.startBlock());

    let auctionCurrencyBalance = 0;
    if (currencyToken === null) {
      auctionCurrencyBalance = Number(await hre.ethers.provider.getBalance(auction.getAddress()));
      auctionCurrencyBalance /= 10 ** 18;
    } else {
      auctionCurrencyBalance = Number(await currencyToken.balanceOf(auction.getAddress()));
      const decimals = await currencyToken.decimals();
      auctionCurrencyBalance /= 10 ** Number(decimals);
    }

    let expectedCurrencyRaised = Number(finalState.currencyRaised);
    if (auctionedToken !== null) {
      const decimals = await auctionedToken.decimals();
      expectedCurrencyRaised /= 10 ** Number(decimals);
    } else {
      throw new Error(ERROR_MESSAGES.AUCTIONED_TOKEN_IS_NULL);
    }

    console.log("\n=== After exit and token claims ===");
    console.log(LOG_PREFIXES.INFO, "Bid count:", bidCount);
    console.log(LOG_PREFIXES.INFO, "Auction duration (blocks):", auctionDurationBlocks);
    console.log(LOG_PREFIXES.INFO, "Auction currency balance:", auctionCurrencyBalance);

    if (totalCurrencyRaised !== -1) {
      console.log(LOG_PREFIXES.INFO, "Actual currency raised (from all bids after refunds):", totalCurrencyRaised);
    }

    console.log(LOG_PREFIXES.INFO, "Expected currency raised (for sweepCurrency()):", expectedCurrencyRaised);
    console.log("\n============================\n");
  }

  private logFinalState(finalState: AuctionState): void {
    console.log(LOG_PREFIXES.CONFIG, "Final state (as of block", finalState.currentBlock + "):");
    console.log("  Is graduated:", finalState.isGraduated);
    console.log("  Clearing price:", finalState.clearingPrice);
    console.log("  Currency raised:", finalState.currencyRaised);
    console.log("  Latest checkpoint:");
    console.log("    Clearing price:", finalState.latestCheckpoint.clearingPrice);
    console.log("    Currency raised (Q96_X7):", finalState.latestCheckpoint.currencyRaisedQ96_X7);
    console.log(
      "    Currency raised at clearing price (Q96_X7):",
      finalState.latestCheckpoint.currencyRaisedAtClearingPriceQ96_X7,
    );
    console.log("    Cumulative MPS per price:", finalState.latestCheckpoint.cumulativeMpsPerPrice);
    console.log("    Cumulative MPS:", finalState.latestCheckpoint.cumulativeMps);
    console.log("    Prev:", finalState.latestCheckpoint.prev);
    console.log("    Next:", finalState.latestCheckpoint.next);
  }

  private generateAddressesForGroups(groups: GroupConfig[]): void {
    for (const group of groups) {
      if (!group.addresses) {
        group.addresses = [];
      }
      for (let i = 0; i < group.count; i++) {
        group.addresses.push(hre.ethers.Wallet.createRandom().address as Address);
      }
    }
  }

  /**
   * Logs balances for all funded accounts showing initial vs final balances
   */
  private async logAccountBalances(
    setupData: TestSetupData,
    deployer: AuctionDeployer,
    auctionedToken: TokenContract | null,
  ): Promise<void> {
    if (!setupData.env.balances || setupData.env.balances.length === 0) return;

    console.log("\n📊 Account Balances Summary:");
    console.log("============================");

    // Collect unique addresses
    const addresses = [...new Set(setupData.env.balances.map((b) => b.address))];

    for (const address of addresses) {
      console.log(`\n${address}:`);

      // Get all initial balances for this address
      const addressBalances = setupData.env.balances.filter((b) => b.address === address);

      // Check each token they were funded with
      for (const initialBalance of addressBalances) {
        const tokenIdentifier = initialBalance.token;
        const initialAmount = BigInt(initialBalance.amount);

        let currentBalance: bigint;
        let tokenSymbol: string;
        let decimals = 18;

        if (tokenIdentifier === ZERO_ADDRESS) {
          // Native ETH
          currentBalance = await hre.ethers.provider.getBalance(address);
          tokenSymbol = NATIVE_CURRENCY_NAME;
        } else {
          // ERC20 token
          const tokenContract = deployer.getTokenByName(tokenIdentifier);
          if (tokenContract) {
            currentBalance = await tokenContract.balanceOf(address);
            tokenSymbol = await tokenContract.symbol();
            decimals = Number(await tokenContract.decimals());
          } else {
            console.log(`  ⚠️  Token ${tokenIdentifier} not found`);
            continue;
          }
        }

        const difference = currentBalance - initialAmount;
        const diffSymbol = difference >= 0n ? "+" : "";
        const diffValue = Number(difference) / 10 ** decimals;

        console.log(`  ${tokenSymbol}:`);
        console.log(`    Initial: ${(Number(initialAmount) / 10 ** decimals).toFixed(6)}`);
        console.log(`    Final:   ${(Number(currentBalance) / 10 ** decimals).toFixed(6)}`);
        console.log(`    Diff:    ${diffSymbol}${diffValue.toFixed(6)}`);
      }

      // Also check auctioned token balance (tokens received from auction)
      if (auctionedToken) {
        const tokenBalance = await auctionedToken.balanceOf(address);
        if (tokenBalance > 0n) {
          const tokenSymbol = await auctionedToken.symbol();
          const decimals = await auctionedToken.decimals();
          console.log(`  ${tokenSymbol} (claimed from auction):`);
          console.log(`    Balance: ${(Number(tokenBalance) / 10 ** Number(decimals)).toFixed(6)}`);
        }
      }
    }

    const auctionCurrency = setupData.auctionParameters.currency;
    const auctionCurrencyIsNative =
      auctionCurrency == ZERO_ADDRESS || (auctionCurrency as string).toLowerCase().includes("native");
    const groupBalances = setupData.env.groups;
    if (groupBalances) {
      for (const group of groupBalances) {
        if (!group.addresses) continue;
        console.log(`\n\n${group.labelPrefix}:`);
        for (let i = 0; i < group.addresses.length; i++) {
          console.log(`\n  Group Member ID: ${group.labelPrefix}-${i}:`);
          const groupMember = group.addresses[i];
          const currentNativeBalance = await hre.ethers.provider.getBalance(groupMember);
          let initialNativeBalance = BigInt(group.startNativeEach ?? "0");
          if (auctionCurrencyIsNative) {
            initialNativeBalance += BigInt(group.startAmountEach ?? "0");
          }

          const difference = currentNativeBalance - initialNativeBalance;
          const diffSymbol = difference >= 0n ? "+" : "";
          const diffValue = Number(difference) / 10 ** 18;

          console.log(`    ${NATIVE_CURRENCY_NAME}:`);
          console.log(`      Initial: ${(Number(initialNativeBalance) / 10 ** 18).toFixed(6)}`);
          console.log(`      Final:   ${(Number(currentNativeBalance) / 10 ** 18).toFixed(6)}`);
          console.log(`      Diff:    ${diffSymbol}${diffValue.toFixed(6)}`);
          if (group.startAmountEach && !auctionCurrencyIsNative) {
            let auctionCurrencyContract: TokenContract | undefined;
            if (auctionCurrency.startsWith("0x")) {
              auctionCurrencyContract = deployer.getTokenByName(auctionCurrency as Address);
            } else {
              auctionCurrencyContract = deployer.getTokenByName(auctionCurrency);
            }
            const currentAuctionCurrencyBalance = await auctionCurrencyContract?.balanceOf(groupMember);
            const initialAuctionCurrencyBalance = BigInt(group.startAmountEach);

            const difference = currentAuctionCurrencyBalance - initialAuctionCurrencyBalance;
            const diffSymbol = difference >= 0n ? "+" : "";

            const decimals = await auctionCurrencyContract?.decimals();
            const diffValue = Number(difference) / 10 ** Number(decimals);

            const tokenSymbol = await auctionCurrencyContract?.symbol();

            console.log(`    ${tokenSymbol}:`);
            console.log(
              `      Initial: ${(Number(initialAuctionCurrencyBalance) / 10 ** Number(decimals)).toFixed(6)}`,
            );
            console.log(
              `      Final:   ${(Number(currentAuctionCurrencyBalance) / 10 ** Number(decimals)).toFixed(6)}`,
            );
            console.log(`      Diff:    ${diffSymbol}${diffValue.toFixed(6)}`);
          }
          if (auctionedToken) {
            const currentAuctionedTokenBalance = await auctionedToken.balanceOf(groupMember);
            if (currentAuctionedTokenBalance == 0n) continue;
            const decimals = await auctionedToken.decimals();

            const tokenSymbol = await auctionedToken.symbol();

            console.log(`    ${tokenSymbol} (claimed from auction):`);
            console.log(
              `      Balance:   ${(Number(currentAuctionedTokenBalance) / 10 ** Number(decimals)).toFixed(6)}`,
            );
          }
        }
      }
    }

    console.log("\n============================\n");
  }

  /**
   * Exit and claim all bids for the auction
   */
  private async exitAndClaimAllBids(
    auction: Contract,
    setupData: TestSetupData,
    currencyToken: TokenContract | null,
    reverseLabelMap: Map<string, string>,
  ): Promise<number> {
    let calculatedCurrencyRaised = 0;
    console.log("\n🎫 Exiting and claiming all bids...");

    // Mine to claim block if needed
    const currentBlock = await hre.ethers.provider.getBlockNumber();
    const claimBlock =
      parseInt(setupData.env.startBlock) +
      setupData.auctionParameters.auctionDurationBlocks +
      setupData.auctionParameters.claimDelayBlocks +
      (setupData.env.offsetBlocks ?? 0);

    if (currentBlock < claimBlock) {
      const blocksToMine = claimBlock - currentBlock;
      await hre.ethers.provider.send("hardhat_mine", [`0x${blocksToMine.toString(16)}`]);
      console.log(`   Mined ${blocksToMine} blocks to reach claim block ${claimBlock}`);
    }

    // Sort checkpoints by block number for searching
    const sortedCheckpoints = [...this.checkpoints].sort((a, b) => a.blockNumber - b.blockNumber);
    const finalCheckpoint = sortedCheckpoints[sortedCheckpoints.length - 1];

    console.log(
      `   📊 ${sortedCheckpoints.length} checkpoints tracked, final clearing: ${
        finalCheckpoint?.clearingPrice || "N/A"
      }`,
    );
    console.log("Sorted checkpoints: ", sortedCheckpoints);
    // Exit and claim for each owner
    for (const [owner, bids] of this.bidsByOwner.entries()) {
      if (bids.length === 0) continue;
      const ownerLabel = reverseLabelMap.get(owner);
      if (ownerLabel) {
        console.log(`\n   ${ownerLabel}: ${bids.length} bid(s)`);
      } else {
        console.log(`\n   ${owner}: ${bids.length} bid(s)`);
      }

      const shouldClaimBid: Map<number, boolean> = new Map();
      let currencyDecimals = 18;
      if (currencyToken !== null) {
        currencyDecimals = await currencyToken.decimals();
      }
      // Exit each bid first
      for (const bid of bids) {
        let balanceBefore = 0n;
        if (currencyToken) {
          balanceBefore = await currencyToken.balanceOf(owner);
        } else {
          balanceBefore = await hre.ethers.provider.getBalance(owner);
        }
        const bidId = bid.bidId;
        const maxPrice = bid.maxPrice;
        // Check if bid is above, at, or below final clearing price
        if (maxPrice > finalCheckpoint.clearingPrice) {
          // Bid is above final clearing - try simple exitBid first
          try {
            let tx = await auction.exitBid(bidId);
            const previousBlock = (await hre.ethers.provider.getBlockNumber()) - 1;
            console.log(`     ✅ Exited bid ${bidId} at block ${previousBlock} (simple exit - above clearing)`);
            shouldClaimBid.set(bidId, true);
            continue; // Successfully exited, move to next bid
          } catch (error) {
            // Simple exit failed, fall through to try partial exit
          }
        }

        // Try partial exit (for bids at/below clearing, or if simple exit failed)
        try {
          const hints = this.findCheckpointHints(maxPrice, sortedCheckpoints);
          if (hints) {
            let tx = await auction.exitPartiallyFilledBid(bidId, hints.lastFullyFilled, hints.outbid);
            const previousBlock = (await hre.ethers.provider.getBlockNumber()) - 1;
            console.log(
              `     ✅ Exited bid ${bidId} at block ${previousBlock} (partial exit with hints: ${hints.lastFullyFilled}, ${hints.outbid})`,
            );
            const receipt = await hre.ethers.provider.getTransactionReceipt(tx.hash);
            for (const log of receipt?.logs ?? []) {
              const parsedLog = auction.interface.parseLog({
                topics: log.topics,
                data: log.data,
              });
              if (parsedLog?.name === EVENTS.BID_EXITED) {
                if (parsedLog.args[2] > 0n) {
                  shouldClaimBid.set(bidId, true);
                }
              }
            }
          } else {
            console.log(`     ⚠️  Could not find checkpoint hints for bid ${bidId} (price: ${maxPrice})`);
          }
        } catch (partialExitError) {
          const errorMsg = partialExitError instanceof Error ? partialExitError.message : String(partialExitError);
          const previousBlock = (await hre.ethers.provider.getBlockNumber()) - 1;
          console.log(`     ⚠️  Could not exit bid ${bidId} at block ${previousBlock}: ${errorMsg.substring(0, 200)}`);
        }
        let balanceAfter = 0n;
        if (currencyToken) {
          balanceAfter = await currencyToken.balanceOf(owner);
        } else {
          balanceAfter = await hre.ethers.provider.getBalance(owner);
        }
        const refundAmount = balanceAfter - balanceBefore;
        calculatedCurrencyRaised += Number(bid.amount - refundAmount) / 10 ** currencyDecimals;
      }

      // Claim all tokens in batch
      const unfilteredBidIds = bids.map((b) => b.bidId);
      const bidIds = unfilteredBidIds.filter((bidId) => shouldClaimBid.get(bidId));
      try {
        await auction.claimTokensBatch(owner, bidIds);
        console.log(`     ✅ Claimed tokens for all bids`);
      } catch (error) {
        console.log(`     ⚠️  Batch claim failed, trying individual claims...`);
        // Fallback to individual claims
        for (const bid of bids) {
          const bidId = bid.bidId;
          try {
            await auction.claimTokens(bidId);
            console.log(`     ✅ Claimed tokens for bid ${bidId}`);
          } catch (e) {
            const errorMsg = e instanceof Error ? e.message : String(e);
            console.log(`     ⚠️  Could not claim bid ${bidId}: ${errorMsg.substring(0, 200)}`);
          }
        }
      }
    }

    return calculatedCurrencyRaised;
  }

  /**
   * Finds checkpoint hints for exiting a partially filled bid
   * @param bidMaxPrice - The maximum price of the bid
   * @param checkpoints - Sorted array of checkpoints
   * @returns Object with lastFullyFilled and outbid block numbers, or null if not applicable
   */
  private findCheckpointHints(
    bidMaxPrice: bigint,
    checkpoints: CheckpointInfo[],
  ): { lastFullyFilled: number; outbid: number } | null {
    // Find lastFullyFilledCheckpoint: last checkpoint where clearingPrice < bidMaxPrice
    let lastFullyFilledBlock = 0;
    for (let i = checkpoints.length - 1; i >= 0; i--) {
      if (checkpoints[i].clearingPrice < bidMaxPrice) {
        lastFullyFilledBlock = checkpoints[i].blockNumber;
        break;
      }
    }

    // Find outbidBlock: first checkpoint where clearingPrice > bidMaxPrice
    let outbidBlock = 0;
    for (let i = 0; i < checkpoints.length; i++) {
      const cp = checkpoints[i];
      if (cp.clearingPrice > bidMaxPrice) {
        outbidBlock = cp.blockNumber;
        break;
      }
    }

    // If we found a fully filled checkpoint but no outbid (bid partially filled at end)
    // or if we found both, return the hints
    if (lastFullyFilledBlock > 0 || outbidBlock > 0) {
      return {
        lastFullyFilled: lastFullyFilledBlock,
        outbid: outbidBlock,
      };
    }

    return null;
  }

  /**
   * Tracks bidIds and checkpoints from events in transaction receipts
   */
  private async trackBidIdsFromReceipts(receipts: any[], auction: Contract): Promise<void> {
    let checkpointCount = 0;

    for (const receipt of receipts) {
      if (!receipt) continue;

      for (const log of receipt.logs) {
        try {
          const parsedLog = auction.interface.parseLog({
            topics: log.topics,
            data: log.data,
          });

          if (parsedLog && parsedLog.name === EVENTS.BID_SUBMITTED) {
            const bidId = Number(parsedLog.args[0]); // bidId
            const owner = parsedLog.args[1]; // owner
            const maxPrice = BigInt(parsedLog.args[2]); // maxPrice
            const amount = BigInt(parsedLog.args[3]); // amount

            const bidInfo: BidInfo = { bidId, owner, maxPrice, amount };

            if (!this.bidsByOwner.has(owner)) {
              this.bidsByOwner.set(owner, []);
            }
            this.bidsByOwner.get(owner)!.push(bidInfo);
          } else if (parsedLog && parsedLog.name === EVENTS.CHECKPOINT_UPDATED) {
            const blockNumber = Number(parsedLog.args[0]); // blockNumber
            const clearingPrice = BigInt(parsedLog.args[1]); // clearingPrice

            this.checkpoints.push({ blockNumber, clearingPrice });
            checkpointCount++;
          }
        } catch (error) {
          // Log parsing failed, continue
          continue;
        }
      }
    }

    if (checkpointCount > 0) {
      console.log(`     📊 ${checkpointCount} checkpoint(s) created`);
    }
  }

  /**
   * Handles initialization transactions for test setup.
   * @param setupTransactions - Array of setup transactions to execute
   */
  async handleInitializeTransactions(setupTransactions: TransactionInfo[]): Promise<void> {
    const provider = hre.ethers.provider;

    // Pause automine so all txs pile up
    await provider.send(METHODS.EVM.SET_AUTOMINE, [false]);
    await provider.send(METHODS.EVM.SET_INTERVAL_MINING, [0]);

    const nextNonce = new Map<string, number>();

    const fee = await hre.ethers.provider.getFeeData();
    const defaultTip = fee.maxPriorityFeePerGas ?? 1n * 10n ** 9n; // 1 gwei
    const defaultMax = fee.maxFeePerGas ?? fee.gasPrice ?? 30n * 10n ** 9n;

    // enqueue all
    for (const job of setupTransactions) {
      const defaultFrom = await (await hre.ethers.getSigners())[0].getAddress();
      const from = hre.ethers.getAddress(job.from ?? defaultFrom); // canonical

      if (job.from) await provider.send(METHODS.HARDHAT.IMPERSONATE_ACCOUNT, [from]);
      const signer = await hre.ethers.getSigner(from);

      const n = nextNonce.has(from) ? nextNonce.get(from)! : await signer.getNonce(PENDING_STATE);

      // base request + fees (don’t rely on global defaults)
      let req: TransactionRequest = {
        ...job.tx,
        nonce: n,
        maxPriorityFeePerGas: job.tx.maxPriorityFeePerGas ?? defaultTip,
        maxFeePerGas: job.tx.maxFeePerGas ?? defaultMax,
      };

      // Cap gas so multiple txs can fit in one block
      if (!req.gasLimit) {
        const est = await signer.estimateGas(req);
        req.gasLimit = (est * 120n) / 100n; // +20% cushion
      }

      await signer.sendTransaction(req); // enqueued; not mined
      nextNonce.set(from, n + 1);
      if (job.from) await provider.send(METHODS.HARDHAT.STOP_IMPERSONATING_ACCOUNT, [from]);
    }

    // mine exactly one block
    await provider.send(METHODS.EVM.MINE, []);

    await provider.send(METHODS.EVM.SET_AUTOMINE, [true]);
  }

  /**
   * Executes all events (bids, actions, assertions) with integrated validation.
   * All events are collected and sorted by block to ensure proper chronological order.
   * Assertions are validated at their specific blocks during execution.
   * Multiple events in the same block are executed together.
   * @param bidSimulator - The bid simulator instance
   * @param assertionEngine - The assertion engine instance
   * @param interactionData - Test interaction data containing bids, actions, and assertions
   * @param remainingTransactions - Array of remaining transactions to execute
   * @param createAuctionBlock - The block number when the auction was started
   */
  async executeWithAssertions(
    bidSimulator: BidSimulator,
    assertionEngine: AssertionEngine,
    interactionData: TestInteractionData,
    remainingTransactions: TransactionInfo[],
    createAuctionBlock: string,
    offsetBlocks: number,
  ): Promise<void> {
    // Collect all events (bids, actions, assertions) and sort by block
    const allEvents: EventData[] = [];

    // Add bids using BidSimulator's collection logic
    const allBids = bidSimulator.collectAllBids(interactionData);
    allBids.forEach((bid) => {
      allEvents.push({
        type: EventType.BID,
        atBlock: bid.bidData.atBlock + offsetBlocks,
        data: bid,
      });
    });

    // Add actions
    if (interactionData.actions) {
      interactionData.actions.forEach((action) => {
        action.interactions.forEach((interactionGroup: AdminAction[] | TransferAction[]) => {
          interactionGroup.forEach((interaction: AdminAction | TransferAction) => {
            allEvents.push({
              type: EventType.ACTION,
              atBlock: interaction.atBlock + offsetBlocks,
              data: { actionType: action.type, ...interaction },
            });
          });
        });
      });
    }

    // Add assertions
    if (interactionData.assertions) {
      interactionData.assertions.forEach((checkpoint) => {
        allEvents.push({
          type: EventType.ASSERTION,
          atBlock: checkpoint.atBlock + offsetBlocks,
          data: checkpoint,
        });
      });
    }
    const accumulatedTransactions: TransactionInfo[] = [];
    // Sort all events by block number, then by type (transactions first, then assertions)
    allEvents.sort((a, b) => {
      if (a.atBlock !== b.atBlock) {
        return a.atBlock - b.atBlock;
      }
      // Within the same block, execute transactions before assertions
      const transactionTypes = [EventType.BID, EventType.ACTION];
      const aIsTransaction = transactionTypes.includes(a.type);
      const bIsTransaction = transactionTypes.includes(b.type);

      if (aIsTransaction && !bIsTransaction) return -1; // a (transaction) comes first
      if (!aIsTransaction && bIsTransaction) return 1; // b (transaction) comes first
      return 0; // same type, maintain original order
    });

    // Group events by block number
    const eventsByBlock: Record<number, EventData[]> = {};
    allEvents.forEach((event) => {
      if (!eventsByBlock[event.atBlock]) {
        eventsByBlock[event.atBlock] = [];
      }
      eventsByBlock[event.atBlock].push(event);
    });

    const totalEvents = allEvents.length;
    const totalBlocks = Object.keys(eventsByBlock).length;
    console.log(LOG_PREFIXES.INFO, "Executing", totalEvents, "events across", totalBlocks, "blocks...");

    // Execute events block by block
    for (const [blockNumber, blockEvents] of Object.entries(eventsByBlock)) {
      if (remainingTransactions.length > 0) {
        if (blockNumber === createAuctionBlock.toString()) {
          accumulatedTransactions.push(...remainingTransactions);
        } else {
          await this.handleTransactions(remainingTransactions, bidSimulator.getReverseLabelMap());
        }
        remainingTransactions = [];
      }
      const blockNum = parseInt(blockNumber);
      console.log(LOG_PREFIXES.INFO, "Block", blockNumber + ":", blockEvents.length, "event(s)");

      // Separate transaction events from assertion events
      const transactionEvents = blockEvents.filter((e) => e.type === EventType.BID || e.type === EventType.ACTION);
      const assertionEvents = blockEvents.filter((e) => e.type === EventType.ASSERTION);

      // Mine to target block ONCE if there are transaction events
      if (transactionEvents.length > 0) {
        const currentBlock = await hre.ethers.provider.getBlockNumber();
        const blocksToMine = blockNum - currentBlock - 1; // Mine to targetBlock - 1

        if (blocksToMine > 0) {
          await this.network.provider.send(METHODS.HARDHAT.MINE, [`0x${blocksToMine.toString(16)}`]);
        } else if (blocksToMine < 0) {
          console.log(LOG_PREFIXES.WARNING, "Block", blockNum, "is already mined. Current block:", currentBlock);
          throw new Error(ERROR_MESSAGES.BLOCK_ALREADY_MINED(blockNum));
        }

        // Execute all transaction events in this block
        for (const event of transactionEvents) {
          console.log(LOG_PREFIXES.INFO, "      -", event.type);
          switch (event.type) {
            case EventType.BID:
              await bidSimulator.executeBid(event.data as InternalBidData, accumulatedTransactions);
              break;
            case EventType.ACTION:
              const actionData = event.data as ActionData;
              if (actionData.actionType === ActionType.TRANSFER_ACTION) {
                await bidSimulator.executeTransfers([actionData as TransferAction], accumulatedTransactions);
              } else if (actionData.actionType === ActionType.ADMIN_ACTION) {
                await bidSimulator.executeAdminActions([actionData as AdminAction], accumulatedTransactions);
              }
              break;
          }
        }
        // Mine the block with all transactions
        await this.handleTransactions(accumulatedTransactions, bidSimulator.getReverseLabelMap());
      }

      // Handle assertion events (after transactions are mined)
      if (assertionEvents.length > 0) {
        // Mine to target block if we haven't already (no transactions case)
        if (transactionEvents.length === 0) {
          const currentBlock = await hre.ethers.provider.getBlockNumber();
          const blocksToMine = blockNum - currentBlock;

          if (blocksToMine > 0) {
            await this.network.provider.send(METHODS.HARDHAT.MINE, [`0x${blocksToMine.toString(16)}`]);
          } else if (blocksToMine < 0) {
            console.log(LOG_PREFIXES.WARNING, "Block", blockNum, "is already mined. Current block:", currentBlock);
            throw new Error(ERROR_MESSAGES.BLOCK_ALREADY_MINED(blockNum));
          }
        }

        // Execute all assertion events in this block
        for (const event of assertionEvents) {
          console.log(LOG_PREFIXES.INFO, "      -", event.type);
          const assertionData = event.data as AssertionInfo;
          console.log(LOG_PREFIXES.INFO, "Validating assertion:", assertionData.reason);
          await assertionEngine.validateAssertion(assertionData.assert);
          console.log(LOG_PREFIXES.SUCCESS, "Assertion validated");
        }
      }
    }
  }

  /**
   * Handles transaction execution with same-block support and revert validation.
   * @param transactions - Array of transactions to execute
   */
  async handleTransactions(transactions: TransactionInfo[], reverseLabelMap: Map<string, string>): Promise<void> {
    const provider = hre.network.provider;

    // Pause automining so txs pile up in the mempool
    await provider.send(METHODS.EVM.SET_AUTOMINE, [false]);
    await provider.send(METHODS.EVM.SET_INTERVAL_MINING, [0]); // ensure no timer mines a block

    const pendingHashes: HashWithRevert[] = [];
    const nextNonce = new Map<string, number>();

    try {
      await this.submitTransactions(transactions, pendingHashes, nextNonce, reverseLabelMap, provider);

      // Mine exactly one block containing all pending txs
      await provider.send(METHODS.EVM.MINE, []);

      const receipts = await this.validateReceipts(pendingHashes);

      // Track bidIds from BidSubmitted events
      if (this.auction && receipts.length > 0) {
        await this.trackBidIdsFromReceipts(receipts, this.auction);
      }
    } finally {
      // Restore automining
      await provider.send(METHODS.EVM.SET_AUTOMINE, [true]);
    }
  }

  /**
   * Submits transactions to the network and tracks them for validation.
   * @param transactions - Array of transactions to submit
   * @param pendingHashes - Array to track transaction hashes with revert information
   * @param nextNonce - Map of addresses to their next nonce values
   * @param provider - The network provider instance
   */
  private async submitTransactions(
    transactions: TransactionInfo[],
    pendingHashes: HashWithRevert[],
    nextNonce: Map<string, number>,
    reverseLabelMap: Map<string, string>,
    provider: any,
  ): Promise<void> {
    while (transactions.length > 0) {
      const txInfo = transactions.shift()!;
      let from = txInfo.from as string;

      if (from) {
        let fromLabel = reverseLabelMap.get(from);
        if (fromLabel) {
          console.log(LOG_PREFIXES.INFO, "From:", from, `(${fromLabel})`);
        } else {
          console.log(LOG_PREFIXES.INFO, "From:", from);
        }
        await provider.send(METHODS.HARDHAT.IMPERSONATE_ACCOUNT, [from]);
      } else {
        const defaultFrom = await (await hre.ethers.getSigners())[0].getAddress();
        from = hre.ethers.getAddress(defaultFrom); // canonical
      }

      const signer = await hre.ethers.getSigner(from);

      // maintain nonce continuity per sender (using "pending" base)
      const n = nextNonce.has(from) ? nextNonce.get(from)! : await signer.getNonce(PENDING_STATE);
      const req = { ...txInfo.tx, nonce: n };
      try {
        const resp = await signer.sendTransaction(req); // just enqueues; not mined
        pendingHashes.push({ hash: resp.hash, expectRevert: txInfo.expectRevert });
        nextNonce.set(from, n + 1);
      } catch (error: any) {
        let matched = false;
        if (txInfo.expectRevert) {
          const errorMessage = error?.message || error?.toString() || "";
          if (txInfo.expectRevert && errorMessage.toLowerCase().includes(txInfo.expectRevert.toLowerCase())) {
            matched = true;
            console.log(LOG_PREFIXES.SUCCESS, `Expected revert caught: ${txInfo.expectRevert}`);
          }
        }
        if (!matched) {
          throw new Error(
            ERROR_MESSAGES.EXPECTED_REVERT_MISMATCH(
              txInfo.expectRevert || "none",
              error instanceof Error ? error.message : String(error),
            ),
          );
        }
      }

      if (from) await provider.send(METHODS.HARDHAT.STOP_IMPERSONATING_ACCOUNT, [from]);
      if (txInfo.msg) console.log(LOG_PREFIXES.TRANSACTION, txInfo.msg);
    }
  }

  /**
   * Validates transaction receipts and checks for expected reverts.
   * @param pendingHashes - Array of transaction hashes with expected revert information
   * @returns Array of receipts for further processing
   */
  private async validateReceipts(pendingHashes: HashWithRevert[]): Promise<any[]> {
    // Collect receipts (all from the same block)
    const receipts = await Promise.all(pendingHashes.map((h) => hre.ethers.provider.getTransactionReceipt(h.hash)));

    for (const pendingHash of pendingHashes) {
      const receipt = receipts.find((r) => r?.hash === pendingHash.hash);
      if (receipt) {
        let decodedRevert: string = "transaction succeeded";
        if (parseBoolean(pendingHash.expectRevert ?? "")) {
          // Status 0 means revert
          if (receipt.status === 0) {
            console.log(LOG_PREFIXES.SUCCESS, `Expected revert caught: ${pendingHash.expectRevert}`);
            continue;
          }
        } else if (pendingHash.expectRevert) {
          // Status 0 means revert
          if (receipt.status === 0) {
            decodedRevert = await this.decodeRevert(pendingHash.hash);
            if (decodedRevert.toLowerCase().includes(pendingHash.expectRevert.toLowerCase())) {
              console.log(LOG_PREFIXES.SUCCESS, `Expected revert caught: ${pendingHash.expectRevert}`);
              continue;
            }
          }
        } else {
          continue;
        }
        throw new Error(ERROR_MESSAGES.EXPECTED_REVERT_MISMATCH(pendingHash.expectRevert || "none", decodedRevert));
      }
    }

    const blockNumber = receipts[0]?.blockNumber;
    if (receipts.length > 0) {
      console.log(LOG_PREFIXES.SUCCESS, "Mined", receipts.length, "txs in block", blockNumber);
    }

    return receipts.filter((r) => r !== null);
  }

  /**
   * Builds an ethers.js Interface for decoding project-specific errors.
   * @returns Interface containing all project error definitions
   */
  async getProjectErrorInterface(): Promise<Interface> {
    if (this.cachedInterface) return this.cachedInterface;

    const fqns = await artifacts.getAllFullyQualifiedNames();

    // Collect JSON ABI items for all custom errors
    const allErrorItems: string[] = [
      // Also include the built-ins as strings
      "error Error(string)",
      "error Panic(uint256)",
    ];

    const seen = new Set<string>(); // dedupe by signature

    for (const fqn of fqns) {
      const art = await artifacts.readArtifact(fqn);
      for (const item of art.abi) {
        if (item.type === TYPES.ERROR) {
          // Build a signature
          const sig = `${item.name}(` + (item.inputs ?? []).map((i: any) => i.type).join(",") + `)`;
          if (seen.has(sig)) continue;
          seen.add(sig);
          allErrorItems.push(item);
        }
      }
    }

    this.cachedInterface = new hre.ethers.Interface(allErrorItems);
    return this.cachedInterface!;
  }

  /**
   * Decodes revert reason from a failed transaction.
   * @param hash - The transaction hash to decode
   * @returns The decoded revert reason
   */
  private async decodeRevert(hash: string): Promise<string> {
    const trace = await hre.network.provider.send(METHODS.DEBUG.TRACE_TRANSACTION, [
      hash,
      { disableStorage: true, disableMemory: true, disableStack: false },
    ]);
    let data = trace.returnValue;
    if (data.slice(0, 2) !== "0x") data = "0x" + data;
    const iface = await this.getProjectErrorInterface();
    try {
      const desc = iface.parseError(data);
      if (desc == null) return "";
      return desc.name + "(" + desc.args.join(",") + ")";
    } catch {
      if (!data || data === "0x") return "";
      return "Unknown error";
    }
  }

  /**
   * Resets the blockchain and deploys Permit2 at the canonical address.
   */
  private async resetChainWithPermit2(): Promise<void> {
    await hre.network.provider.send(METHODS.HARDHAT.RESET);
    // Check if Permit2 is already deployed at the canonical address
    const code = await hre.ethers.provider.getCode(PERMIT2_ADDRESS);

    if (code === "0x") {
      console.log(LOG_PREFIXES.INFO, "Deploying Permit2 at canonical address...");

      // Load the Permit2 artifact
      // TODO: find a way to avoid require
      const permit2Artifact = require("../../../lib/permit2/out/Permit2.sol/Permit2.json");

      // Deploy Permit2 using the factory pattern first, then move to canonical address
      const permit2Factory = await hre.ethers.getContractFactory(permit2Artifact.abi, permit2Artifact.bytecode.object);

      // Deploy Permit2 normally first
      const permit2Contract = await permit2Factory.deploy();
      await permit2Contract.waitForDeployment();
      const permit2Address = await permit2Contract.getAddress();

      // Get the deployed bytecode
      const deployedCode = await hre.ethers.provider.getCode(permit2Address);
      await hre.network.provider.send(METHODS.HARDHAT.RESET);
      // Set code at canonical address
      await hre.network.provider.send(METHODS.HARDHAT.SET_CODE, [PERMIT2_ADDRESS, deployedCode]);

      console.log(LOG_PREFIXES.SUCCESS, "Permit2 deployed at canonical address");
    } else {
      console.log(LOG_PREFIXES.SUCCESS, "Permit2 already deployed at canonical address");
    }
  }
}
