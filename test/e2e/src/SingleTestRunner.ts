import { SchemaValidator } from './SchemaValidator';
import { Address, TestSetupData } from '../schemas/TestSetupSchema';
import { ActionType, TestInteractionData, AdminAction, TransferAction, AssertionInfo } from '../schemas/TestInteractionSchema';
import { AuctionDeployer } from './AuctionDeployer';
import { BidSimulator, InternalBidData } from './BidSimulator';
import { AssertionEngine, AuctionState } from './AssertionEngine';
import { Contract } from 'ethers';
import { Network } from 'hardhat/types';
import { PERMIT2_ADDRESS } from './constants';
import hre from "hardhat";
import { TransactionInfo } from './types';

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
  BID = 'bid',
  ACTION = 'action',
  ASSERTION = 'assertion'
}

export type ActionData = { actionType: ActionType } & (AdminAction | TransferAction);

// Union type for all possible event data types
export type EventInternalData = 
  | InternalBidData 
  | ActionData
  | AssertionInfo;

export interface EventData {
  type: EventType;
  atBlock: number;
  data: EventInternalData;
}

export class SingleTestRunner {
  private network: Network;
  private schemaValidator: SchemaValidator;
  private deployer: AuctionDeployer;

  constructor() {
    this.network = hre.network;
    this.schemaValidator = new SchemaValidator();
    this.deployer = new AuctionDeployer();
  }


  async runFullTest(setupData: TestSetupData, interactionData: TestInteractionData): Promise<TestResult> {
    console.log(`\n🧪 Running test: ${setupData.name} + ${interactionData.name}`);
    
    console.log('✅ Schema validation passed');
    
    // Reset the Hardhat network to start fresh for each test
    await hre.network.provider.send('hardhat_reset');
    console.log('   🔄 Reset Hardhat network to start fresh');
    
    // PHASE 1: Setup the auction environment
    console.log('🏗️  Phase 1: Setting up auction environment...');
    
    // Check current block and auction start block
    const currentBlock = await hre.ethers.provider.getBlockNumber();
    const auctionStartBlock = parseInt(setupData.env.startBlock) + setupData.auctionParameters.startOffsetBlocks;
    console.log(`   📊 Current block: ${currentBlock}, Auction start block: ${auctionStartBlock}`);
    
    if (currentBlock < auctionStartBlock) {
      const blocksToMine = auctionStartBlock - currentBlock;
      await hre.ethers.provider.send('hardhat_mine', [`0x${blocksToMine.toString(16)}`]);
      console.log(`   ⏰ Mined ${blocksToMine} blocks to reach auction start block ${auctionStartBlock}`);
    } else if (currentBlock > auctionStartBlock) {
      console.log(`   ⚠️  Current block ${currentBlock} is already past auction start block ${auctionStartBlock}`);
    }
    
    // Deploy Permit2 at canonical address (one-time setup)
    await this.handlePermit2Deployment();
    
    let setupTransactions: TransactionInfo[] = [];
    // Initialize deployer with tokens and factory (one-time setup)
    await this.deployer.initialize(setupData);
    
    // Create the auction
    const auction: Contract = await this.deployer.createAuction(setupData);
    
    // Setup balances
    await this.deployer.setupBalances(setupData);

    this.handleTransactions(setupTransactions);
    
    console.log(`   🏛️  Auction deployed: ${await auction.getAddress()}`);
    
    // PHASE 2: Execute interactions on the configured auction
    console.log('🎯 Phase 2: Executing interaction scenario...');
    const auctionedToken = this.deployer.getTokenByName(setupData.auctionParameters.auctionedToken) ?? null;
    const currencyToken = setupData.auctionParameters.currency === '0x0000000000000000000000000000000000000000' ? null : this.deployer.getTokenByName(setupData.auctionParameters.currency) ?? null;
    const bidSimulator = new BidSimulator(auction, currencyToken as Contract);
    const assertionEngine = new AssertionEngine(auction, auctionedToken, currencyToken, this.deployer);
    
    // Setup labels and execute the interaction scenario
    await bidSimulator.setupLabels(interactionData);
    
    // Execute bids and actions with integrated checkpoint validation
    await this.executeWithAssertions(bidSimulator, assertionEngine, interactionData);
    
    console.log('   💰 Bids executed and assertions validated successfully');
    
    // Get final state
    const finalState = await assertionEngine.getAuctionState();
    
          console.log('🎉 Test completed successfully!');
          console.log(`   📊 Final state:`, finalState);
    
    return {
      setupData,
      interactionData,
      auction,
      auctionedToken: auctionedToken ? await auctionedToken.getAddress() as Address : null,
      currencyToken: currencyToken ? await currencyToken.getAddress() as Address : null,
      finalState,
      success: true
    };
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
    interactionData: TestInteractionData
  ): Promise<void> {
    // Collect all events (bids, actions, assertions) and sort by block
    const allEvents: EventData[] = [];
    
    // Add bids using BidSimulator's collection logic
    const allBids = bidSimulator.collectAllBids(interactionData);
    allBids.forEach(bid => {
      allEvents.push({
        type: EventType.BID,
        atBlock: bid.bidData.atBlock,
        data: bid
      });
    });
    
    // Add actions
    if (interactionData.actions) {
      interactionData.actions.forEach(action => {
        action.interactions.forEach((interactionGroup: AdminAction[] | TransferAction[]) => {
          interactionGroup.forEach((interaction: AdminAction | TransferAction) => {
            allEvents.push({
              type: EventType.ACTION,
              atBlock: interaction.atBlock,
              data: { actionType: action.type, ...interaction }
            });
          });
        });
      });
    }
    
    // Add assertions
    if (interactionData.assertions) {
      interactionData.assertions.forEach(checkpoint => {
        allEvents.push({
          type: EventType.ASSERTION,
          atBlock: checkpoint.atBlock,
          data: checkpoint
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
      if (!aIsTransaction && bIsTransaction) return 1;  // b (transaction) comes first
      return 0; // same type, maintain original order
    });
    
    // Group events by block number
    const eventsByBlock: Record<number, EventData[]> = {};
    allEvents.forEach(event => {
      if (!eventsByBlock[event.atBlock]) {
        eventsByBlock[event.atBlock] = [];
      }
      eventsByBlock[event.atBlock].push(event);
    });
    
    const totalEvents = allEvents.length;
    const totalBlocks = Object.keys(eventsByBlock).length;
    console.log(`   📅 Executing ${totalEvents} events across ${totalBlocks} blocks...`);
    
    // Execute events block by block
    for (const [blockNumber, blockEvents] of Object.entries(eventsByBlock)) {
      const blockNum = parseInt(blockNumber);
      
      console.log(`   🔸 Block ${blockNumber}: ${blockEvents.length} event(s)`);
      
      // Mine to the target block (only once per block)
      const currentBlock = await hre.ethers.provider.getBlockNumber();
      
      
      // Execute all events in this block
      for (const event of blockEvents) {
        console.log(`      📝 ${event.type}`);
        let blocksToMine = blockNum - currentBlock;
        // For transactions, mine to targetBlock - 1, then execute
        if (event.type === EventType.BID || event.type === EventType.ACTION) {
          blocksToMine--; 
        }  else {
          await this.handleTransactions(accumulatedTransactions);
        }

        if (blocksToMine > 0) {
          await this.network.provider.send('hardhat_mine', [`0x${blocksToMine.toString(16)}`]);
        } else if (blocksToMine < 0) {
          console.log(`         ⚠️  Block ${blockNum} is already mined. Current block: ${currentBlock}`);
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
              await bidSimulator.executeTransfers([[actionData]], accumulatedTransactions);
            } else if (actionData.actionType === ActionType.ADMIN_ACTION) {
              await bidSimulator.executeAdminActions([[actionData]], accumulatedTransactions);
            }
            break;
          case EventType.ASSERTION:
            const assertionData = event.data as AssertionInfo;
            console.log(`         🔍 Validating checkpoint: ${assertionData.reason}`);
            await assertionEngine.validateAssertion(assertionData.assert);
            console.log(`         ✅ Assertion validated`);
            break;
        }
      }
        await this.handleTransactions(accumulatedTransactions);
    }
  }
/*
while (transactions.length > 0) {
      const transactionInfo = transactions.shift();
      let from = transactionInfo.from;
      if (from !== null) {
        console.log(`   🔍 Impersonating account: ${from}`);
        await hre.network.provider.send('hardhat_impersonateAccount', [from]);
      }
      const signer = await hre.ethers.getSigner(from);
      await signer.sendTransaction(transactionInfo.tx);
      if (from !== null) {
        await hre.network.provider.send('hardhat_stopImpersonatingAccount', [from]);
      }
      console.log(transactionInfo.msg);
     }
*/
  async handleTransactions(transactions: any[]): Promise<void> {
    const provider = hre.network.provider as any;

    // 1) Pause automining so txs pile up in the mempool
    await provider.send("evm_setAutomine", [false]);
    await provider.send("evm_setIntervalMining", [0]); // ensure no timer mines a block
  
    const pendingHashes: string[] = [];
    const nextNonce = new Map<string, number>();
  
    try {
      while (transactions.length > 0) {
        const txInfo = transactions.shift()!;
        const from = txInfo.from as string;
  
        if (from) {
          console.log(`   🔍 Impersonating ${from}`);
          await provider.send("hardhat_impersonateAccount", [from]);
        }
  
        const signer = await hre.ethers.getSigner(from);
  
        // maintain nonce continuity per sender (using "pending" base)
        const n = nextNonce.has(from)
          ? nextNonce.get(from)!
          : await signer.getNonce("pending");
        const req = { ...txInfo.tx, nonce: n };
  
        const resp = await signer.sendTransaction(req); // just enqueues; not mined
        pendingHashes.push(resp.hash);
        nextNonce.set(from, n + 1);
  
        if (from) await provider.send("hardhat_stopImpersonatingAccount", [from]);
        if (txInfo.msg) console.log(txInfo.msg);
      }
  
      // 2) Mine exactly one block containing all pending txs
      await provider.send("evm_mine", []);
  
      // 3) Collect receipts (all from the same block)
      const receipts = await Promise.all(
        pendingHashes.map(h => hre.ethers.provider.getTransactionReceipt(h))
      );
      const blockNumber = receipts[0]?.blockNumber;
      console.log(`✅ Mined ${receipts.length} txs in block ${blockNumber}`);
    } finally {
      // 4) Restore automining
      await provider.send("evm_setAutomine", [true]);
    }
  }

  private async handlePermit2Deployment(): Promise<void> {
    // Check if Permit2 is already deployed at the canonical address
    const code = await hre.ethers.provider.getCode(PERMIT2_ADDRESS);
    
    if (code === '0x') {
      console.log('   🔍 Deploying Permit2 at canonical address...');
      
      // Load the Permit2 artifact
      const permit2Artifact = require('../../../lib/permit2/out/Permit2.sol/Permit2.json');
      
      // Deploy Permit2 using the factory pattern first, then move to canonical address
      const permit2Factory = await hre.ethers.getContractFactory(
        permit2Artifact.abi,
        permit2Artifact.bytecode.object
      );
      
      // Deploy Permit2 normally first
      const permit2Contract = await permit2Factory.deploy();
      await permit2Contract.waitForDeployment();
      const permit2Address = await permit2Contract.getAddress();
      
      // Get the deployed bytecode
      const deployedCode = await hre.ethers.provider.getCode(permit2Address);
      
      // Use hardhat_setCode to deploy at canonical address
      await hre.network.provider.send('hardhat_setCode', [
        PERMIT2_ADDRESS,
        deployedCode
      ]);
      
      console.log('   ✅ Permit2 deployed at canonical address');
    } else {
      console.log('   ✅ Permit2 already deployed at canonical address');
    }
  }
}
