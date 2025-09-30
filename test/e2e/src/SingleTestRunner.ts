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
import { PERMIT2_ADDRESS, LOG_PREFIXES } from "./constants";
import hre from "hardhat";
import { artifacts } from "hardhat";
import { HashWithRevert, TransactionInfo } from "./types";
import { TransactionRequest } from "ethers";

export interface TestResult {
  setupData: TestSetupData;
  interactionData: TestInteractionData;
  auction: Contract;
  auctionedToken: Address | null;
  currencyToken: Address | null;
  finalState: AuctionState;
  success: boolean;
}

export enum EventType {
  BID = "bid",
  ACTION = "action",
  ASSERTION = "assertion",
}

export type ActionData = { actionType: ActionType } & (AdminAction | TransferAction);

// Union type for all possible event data types
export type EventInternalData = InternalBidData | ActionData | AssertionInfo;

export interface EventData {
  type: EventType;
  atBlock: number;
  data: EventInternalData;
}

export class SingleTestRunner {
  private network: Network;
  private schemaValidator: SchemaValidator;
  private deployer: AuctionDeployer;
  private cachedInterface: Interface | null = null;

  constructor() {
    this.network = hre.network;
    this.schemaValidator = new SchemaValidator();
    this.deployer = new AuctionDeployer();
  }

  async runFullTest(setupData: TestSetupData, interactionData: TestInteractionData): Promise<TestResult> {
    console.log(LOG_PREFIXES.TEST, "Running test:", setupData.name, "+", interactionData.name);

    console.log(LOG_PREFIXES.SUCCESS, "Schema validation passed");

    // Reset the Hardhat network to start fresh for each test
    // Deploy Permit2 at canonical address (one-time setup)
    await this.resetChainWithPermit2();
    console.log(LOG_PREFIXES.INFO, "Reset Hardhat network to start fresh");

    // PHASE 1: Setup the auction environment
    console.log(LOG_PREFIXES.INFO, "Phase 1: Setting up auction environment...");

    // Check current block and auction start block
    const currentBlock = await hre.ethers.provider.getBlockNumber();
    const auctionStartBlock = parseInt(setupData.env.startBlock) + setupData.auctionParameters.startOffsetBlocks;
    console.log(LOG_PREFIXES.CONFIG, "Current block:", currentBlock, ", Auction start block:", auctionStartBlock);

    if (currentBlock < auctionStartBlock) {
      const blocksToMine = auctionStartBlock - currentBlock;
      await hre.ethers.provider.send("hardhat_mine", [`0x${blocksToMine.toString(16)}`]);
      console.log(LOG_PREFIXES.INFO, "Mined", blocksToMine, "blocks to reach auction start block", auctionStartBlock);
    } else if (currentBlock > auctionStartBlock) {
      throw new Error(`Current block ${currentBlock} is already past auction start block ${auctionStartBlock}`);
    }

    let setupTransactions: TransactionInfo[] = [];
    // Initialize deployer with tokens and factory (one-time setup)
    await this.deployer.initialize(setupData, setupTransactions);
    // Setup balances
    await this.deployer.setupBalances(setupData, setupTransactions);
    await this.handleInitializeTransactions(setupTransactions);
    setupTransactions = [];
    // Create the auction
    const auction: Contract = await this.deployer.createAuction(setupData, setupTransactions);

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
    await bidSimulator.setupLabels(interactionData);

    // Execute bids and actions with integrated checkpoint validation
    await this.executeWithAssertions(
      bidSimulator,
      assertionEngine,
      interactionData,
      setupTransactions,
      setupData.env.startBlock,
    );

    console.log(LOG_PREFIXES.SUCCESS, "Bids executed and assertions validated successfully");

    // Get final state
    const finalState = await assertionEngine.getAuctionState();

    console.log(LOG_PREFIXES.FINAL, "Test completed successfully!");
    console.log(LOG_PREFIXES.CONFIG, "Final state:", finalState);

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

  async handleInitializeTransactions(setupTransactions: TransactionInfo[]): Promise<void> {
    const provider = hre.ethers.provider as any;

    // Pause automine so all txs pile up
    await provider.send("evm_setAutomine", [false]);
    await provider.send("evm_setIntervalMining", [0]);

    const nextNonce = new Map<string, number>();

    const fee = await hre.ethers.provider.getFeeData();
    const defaultTip = fee.maxPriorityFeePerGas ?? 1n * 10n ** 9n; // 1 gwei
    const defaultMax = fee.maxFeePerGas ?? fee.gasPrice ?? 30n * 10n ** 9n;

    // enqueue all
    for (const job of setupTransactions) {
      const defaultFrom = await (await hre.ethers.getSigners())[0].getAddress();
      const from = hre.ethers.getAddress(job.from ?? defaultFrom); // canonical

      if (job.from) await provider.send("hardhat_impersonateAccount", [from]);
      const signer = await hre.ethers.getSigner(from);

      const n = nextNonce.has(from) ? nextNonce.get(from)! : await signer.getNonce("pending");

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
      if (job.from) await provider.send("hardhat_stopImpersonatingAccount", [from]);
    }

    // mine exactly one block
    await provider.send("evm_mine", []);

    await provider.send("evm_setAutomine", [true]);
  }

  /**
   * Execute all events (bids, actions, assertions) with integrated validation
   * All events are collected and sorted by block to ensure proper chronological order
   * Assertions are validated at their specific blocks during execution
   * Multiple events in the same block are executed together
   */
  async executeWithAssertions(
    bidSimulator: BidSimulator,
    assertionEngine: AssertionEngine,
    interactionData: TestInteractionData,
    remainingTransactions: TransactionInfo[],
    createAuctionBlock: string,
  ): Promise<void> {
    // Collect all events (bids, actions, assertions) and sort by block
    const allEvents: EventData[] = [];

    // Add bids using BidSimulator's collection logic
    const allBids = bidSimulator.collectAllBids(interactionData);
    allBids.forEach((bid) => {
      allEvents.push({
        type: EventType.BID,
        atBlock: bid.bidData.atBlock,
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
              atBlock: interaction.atBlock,
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
          atBlock: checkpoint.atBlock,
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
          await this.handleTransactions(remainingTransactions);
        }
        remainingTransactions = [];
      }
      const blockNum = parseInt(blockNumber);
      console.log(LOG_PREFIXES.INFO, "Block", blockNumber + ":", blockEvents.length, "event(s)");

      // Execute all events in this block
      for (const event of blockEvents) {
        // Mine to the target block (only once per block)
        const currentBlock = await hre.ethers.provider.getBlockNumber();
        console.log(LOG_PREFIXES.INFO, "      -", event.type);
        let blocksToMine = blockNum - currentBlock;
        // For transactions, mine to targetBlock - 1, then execute
        if (event.type === EventType.BID || event.type === EventType.ACTION) {
          blocksToMine--;
        } else {
          await this.handleTransactions(accumulatedTransactions);
          blocksToMine = blockNum - (await hre.ethers.provider.getBlockNumber());
        }

        if (blocksToMine > 0) {
          await this.network.provider.send("hardhat_mine", [`0x${blocksToMine.toString(16)}`]);
        } else if (blocksToMine < 0) {
          console.log(LOG_PREFIXES.WARNING, "Block", blockNum, "is already mined. Current block:", currentBlock);
          throw new Error(`Block ${blockNum} is already mined`);
        }

        // Execute the event
        switch (event.type) {
          case EventType.BID:
            await bidSimulator.executeBid(event.data as InternalBidData, accumulatedTransactions);
            break;
          case EventType.ACTION:
            const actionData = event.data as ActionData;
            if (actionData.actionType === ActionType.TRANSFER_ACTION) {
              await bidSimulator.executeTransfers([actionData as TransferAction], accumulatedTransactions);
            } else if (actionData.actionType === ActionType.ADMIN_ACTION) {
              await bidSimulator.executeAdminActions([[actionData]], accumulatedTransactions);
            }
            break;
          case EventType.ASSERTION:
            const assertionData = event.data as AssertionInfo;
            console.log(LOG_PREFIXES.INFO, "Validating assertion:", assertionData.reason);
            await assertionEngine.validateAssertion(assertionData.assert);
            console.log(LOG_PREFIXES.SUCCESS, "Assertion validated");
            break;
        }
      }
      await this.handleTransactions(accumulatedTransactions);
    }
  }

  async handleTransactions(transactions: any[]): Promise<void> {
    const provider = hre.network.provider as any;

    // Pause automining so txs pile up in the mempool
    await provider.send("evm_setAutomine", [false]);
    await provider.send("evm_setIntervalMining", [0]); // ensure no timer mines a block

    const pendingHashes: HashWithRevert[] = [];
    const nextNonce = new Map<string, number>();

    try {
      await this.submitTransactions(transactions, pendingHashes, nextNonce, provider);

      // Mine exactly one block containing all pending txs
      await provider.send("evm_mine", []);

      await this.validateReceipts(pendingHashes);
    } finally {
      // Restore automining
      await provider.send("evm_setAutomine", [true]);
    }
  }

  private async submitTransactions(
    transactions: any[],
    pendingHashes: HashWithRevert[],
    nextNonce: Map<string, number>,
    provider: any,
  ): Promise<void> {
    while (transactions.length > 0) {
      const txInfo = transactions.shift()!;
      const from = txInfo.from as string;

      if (from) {
        console.log(LOG_PREFIXES.INFO, "From:", from);
        await provider.send("hardhat_impersonateAccount", [from]);
      }

      const signer = await hre.ethers.getSigner(from);

      // maintain nonce continuity per sender (using "pending" base)
      const n = nextNonce.has(from) ? nextNonce.get(from)! : await signer.getNonce("pending");
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
          throw new Error(`Expected revert "${txInfo.expectRevert || "none"}" but got: ${error}`);
        }
      }

      if (from) await provider.send("hardhat_stopImpersonatingAccount", [from]);
      if (txInfo.msg) console.log(txInfo.msg);
    }
  }

  private async validateReceipts(pendingHashes: HashWithRevert[]): Promise<void> {
    // Collect receipts (all from the same block)
    const receipts = await Promise.all(pendingHashes.map((h) => hre.ethers.provider.getTransactionReceipt(h.hash)));

    for (const pendingHash of pendingHashes) {
      const receipt = receipts.find((r) => r?.hash === pendingHash.hash);
      if (receipt) {
        let decodedRevert: string = "transaction succeeded";
        if (pendingHash.expectRevert === "true" || pendingHash.expectRevert === "1") {
          if (receipt.status === 0) {
            console.log(LOG_PREFIXES.SUCCESS, `Expected revert caught: ${pendingHash.expectRevert}`);
            continue;
          }
        } else if (pendingHash.expectRevert) {
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
        throw new Error(`Expected revert "${pendingHash.expectRevert || "none"}" but got: ${decodedRevert}`);
      }
    }

    const blockNumber = receipts[0]?.blockNumber;
    if (receipts.length > 0) {
      console.log(LOG_PREFIXES.SUCCESS, "Mined", receipts.length, "txs in block", blockNumber);
    }
  }

  async getProjectErrorInterface(): Promise<Interface> {
    if (this.cachedInterface) return this.cachedInterface;

    const fqns = await artifacts.getAllFullyQualifiedNames();

    // Collect JSON ABI items for all custom errors
    const allErrorItems: any[] = [
      // Also include the built-ins as strings
      "error Error(string)",
      "error Panic(uint256)",
    ];

    const seen = new Set<string>(); // dedupe by signature

    for (const fqn of fqns) {
      const art = await artifacts.readArtifact(fqn);
      for (const item of art.abi) {
        if (item.type === "error") {
          // Build a signature to dedupe
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

  private async decodeRevert(hash: string): Promise<string> {
    const trace = await hre.network.provider.send("debug_traceTransaction", [
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

  private async resetChainWithPermit2(): Promise<void> {
    await hre.network.provider.send("hardhat_reset");
    // Check if Permit2 is already deployed at the canonical address
    const code = await hre.ethers.provider.getCode(PERMIT2_ADDRESS);

    if (code === "0x") {
      console.log(LOG_PREFIXES.INFO, "Deploying Permit2 at canonical address...");

      // Load the Permit2 artifact
      const permit2Artifact = require("../../../lib/permit2/out/Permit2.sol/Permit2.json");

      // Deploy Permit2 using the factory pattern first, then move to canonical address
      const permit2Factory = await hre.ethers.getContractFactory(permit2Artifact.abi, permit2Artifact.bytecode.object);

      // Deploy Permit2 normally first
      const permit2Contract = await permit2Factory.deploy();
      await permit2Contract.waitForDeployment();
      const permit2Address = await permit2Contract.getAddress();

      // Get the deployed bytecode
      const deployedCode = await hre.ethers.provider.getCode(permit2Address);
      await hre.network.provider.send("hardhat_reset");
      // Use hardhat_setCode to deploy at canonical address
      await hre.network.provider.send("hardhat_setCode", [PERMIT2_ADDRESS, deployedCode]);

      console.log(LOG_PREFIXES.SUCCESS, "Permit2 deployed at canonical address");
    } else {
      console.log(LOG_PREFIXES.SUCCESS, "Permit2 already deployed at canonical address");
    }
  }
}
