import { SchemaValidator } from './SchemaValidator';
import { Address, TestSetupData } from '../schemas/TestSetupSchema';
import { ActionType, TestInteractionData, AdminAction, TransferAction, AssertionInfo } from '../schemas/TestInteractionSchema';
import { AuctionDeployer } from './AuctionDeployer';
import { BidSimulator, InternalBidData } from './BidSimulator';
import { AssertionEngine, AuctionState } from './AssertionEngine';
import { Contract } from 'ethers';
import hre from "hardhat";
import { Network } from 'hardhat/types';

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
  private network: Network; // Hardhat network type is complex, using any for now
  private schemaValidator: SchemaValidator;
  private deployer: AuctionDeployer;

  constructor() {
    this.network = hre.network;
    this.schemaValidator = new SchemaValidator();
    this.deployer = new AuctionDeployer();
  }

  /**
   * Runs a complete test combining setup and interaction schemas
   */
  async runCombinedTest(setupFilename: string, interactionFilename: string): Promise<TestResult> {
    console.log(`\n🧪 Running combined test: ${setupFilename} + ${interactionFilename}`);
    
    // Load and validate both schemas
    const setupData = this.schemaValidator.loadTestInstance('setup', setupFilename) as TestSetupData;
    const interactionData = this.schemaValidator.loadTestInstance('interaction', interactionFilename) as TestInteractionData;
    
    console.log('✅ Schema validation passed');
    
    // PHASE 1: Setup the auction environment
    console.log('🏗️  Phase 1: Setting up auction environment...');
    
    // Initialize deployer with tokens and factory (one-time setup)
    await this.deployer.initialize(setupData);
    
    // Create the auction
    const auction: Contract = await this.deployer.createAuction(setupData);
    
    // Setup balances
    await this.deployer.setupBalances(setupData);
    
    console.log(`   🏛️  Auction deployed: ${await auction.getAddress()}`);
    
    // PHASE 2: Execute interactions on the configured auction
    console.log('🎯 Phase 2: Executing interaction scenario...');
    const auctionedToken = this.deployer.getTokenByName(setupData.auctionParameters.auctionedToken);
    const currencyToken = setupData.auctionParameters.currency === '0x0000000000000000000000000000000000000000' ? null : this.deployer.getTokenByName(setupData.auctionParameters.currency);
    const bidSimulator = new BidSimulator(auction, currencyToken as Contract);
    const assertionEngine = new AssertionEngine(auction, auctionedToken as any, currencyToken as any, this.deployer);
    
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
    
    // Sort all events by block number, then by type (queries first, then transactions)
    allEvents.sort((a, b) => {
      if (a.atBlock !== b.atBlock) {
        return a.atBlock - b.atBlock;
      }
      // Within the same block, execute queries/assertions before transactions
      const queryTypes = [EventType.ASSERTION];
      const aIsQuery = queryTypes.includes(a.type);
      const bIsQuery = queryTypes.includes(b.type);
      
      if (aIsQuery && !bIsQuery) return -1; // a (query) comes first
      if (!aIsQuery && bIsQuery) return 1;  // b (query) comes first
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
      
      // Mine to the target block (only once per block)
      await this.network.provider.send('hardhat_mine', [blockNumber]);
      
      console.log(`   🔸 Block ${blockNumber}: ${blockEvents.length} event(s)`);
      
      // Execute all events in this block
      for (const event of blockEvents) {
        console.log(`      📝 ${event.type}`);
        console.log(event.data);
        // Execute the event
        switch (event.type) {
          case EventType.BID:
            await bidSimulator.executeBid(event.data as InternalBidData);
            break;
          case EventType.ACTION:
            const actionData = event.data as ActionData;
            if (actionData.actionType === ActionType.TRANSFER_ACTION) {
              await bidSimulator.executeTransfers([[actionData]]);
            } else if (actionData.actionType === ActionType.ADMIN_ACTION) {
              await bidSimulator.executeAdminActions([[actionData]]);
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
    }
  }

}
