import { SchemaValidator } from './SchemaValidator';
import { Address, TestSetupData } from '../schemas/TestSetupSchema';
import { ActionType, TestInteractionData } from '../schemas/TestInteractionSchema';
import { AuctionDeployer } from './AuctionDeployer';
import { BidSimulator } from './BidSimulator';
import { AssertionEngine, AuctionState } from './AssertionEngine';
import { Contract } from 'ethers';
import hre from "hardhat";

export interface TestResult {
  setupData: TestSetupData;
  interactionData: TestInteractionData;
  auction: Contract;
  auctionedToken: Address;
  currencyToken: Address;
  finalState: AuctionState;
  success: boolean;
}

export enum EventType {
  BID = 'bid',
  GROUP_BID = 'groupBid',
  ACTION = 'action',
  ASSERTION = 'assertion'
}

export interface EventData {
  type: EventType;
  atBlock: number;
  data: any;
}

export class SingleTestRunner {
  private network: any;
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
    const auction: Contract = await this.deployer.createAuction(setupData);
    await this.deployer.setupBalances(setupData);
    
    console.log(`   🏛️  Auction deployed: ${await auction.getAddress()}`);
    
    // PHASE 2: Execute interactions on the configured auction
    console.log('🎯 Phase 2: Executing interaction scenario...');
    const auctionedToken = this.deployer.getTokenByName(setupData.auctionParameters.auctionedToken);
    const currencyToken = setupData.auctionParameters.currency === '0x0000000000000000000000000000000000000000' ? null : this.deployer.getTokenByName(setupData.auctionParameters.currency);
    const bidSimulator = new BidSimulator(auction, currencyToken || null);
    const assertionEngine = new AssertionEngine(auction, auctionedToken || null, currencyToken || null, this.deployer);
    
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
      auctionedToken: auctionedToken || null,
      currencyToken: currencyToken || null,
      finalState,
      success: true
    };
  }

  /**
   * Execute bids and actions with integrated assertion validation
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
    
    // Add bids
    if (interactionData.namedBidders) {
      interactionData.namedBidders.forEach(bidder => {
        bidder.bids.forEach(bid => {
          allEvents.push({
            type: EventType.BID,
            atBlock: bid.atBlock,
            data: {
              bidData: bid,
              bidder: bidder.address,
              type: 'named' as const
            }
          });
        });
      });
    }
    
    // Add group bids
    if (interactionData.groups) {
      interactionData.groups.forEach(group => {
        const bidders = bidSimulator.getGroupBidders(group.labelPrefix);
        if (bidders) {
          for (let round = 0; round < group.rounds; round++) {
            for (let i = 0; i < group.count; i++) {
              const bidder = bidders[i];
              const atBlock = group.startBlock + 
                (round * (group.rotationIntervalBlocks + group.betweenRoundsBlocks)) +
                (i * group.rotationIntervalBlocks);
              
              allEvents.push({
                type: EventType.GROUP_BID,
                atBlock: atBlock,
                data: {
                  bidData: {
                    atBlock: atBlock,
                    amount: group.amount,
                    price: group.price,
                    previousTick: group.previousTick,
                    hookData: group.hookData
                  },
                  bidder: bidder,
                  type: 'group' as const,
                  group: group.labelPrefix
                }
              });
            }
          }
        }
      });
    }
    
    // Add actions
    if (interactionData.actions) {
      interactionData.actions.forEach(action => {
        action.interactions.forEach((interactionGroup: any) => {
          interactionGroup.forEach((interaction: any) => {
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
            await bidSimulator.executeBid(event.data);
            break;
          case EventType.GROUP_BID:
            await bidSimulator.executeBid(event.data);
            break;
          case EventType.ACTION:
            if (event.data.actionType === ActionType.TRANSFER_ACTION) {
              await bidSimulator.executeTransfers([[event.data]]);
            } else if (event.data.actionType === ActionType.ADMIN_ACTION) {
              await bidSimulator.executeAdminActions([[event.data]]);
            }
            break;
          case EventType.ASSERTION:
            console.log(`         🔍 Validating checkpoint: ${event.data.reason}`);
            await assertionEngine.validateAssertion(event.data.assert);
            console.log(`         ✅ Assertion validated`);
            break;
        }
      }
    }
  }

}
