import { SchemaValidator, SetupData, InteractionData } from './SchemaValidator';
import { AuctionDeployer } from './AuctionDeployer';
import { BidSimulator } from './BidSimulator';
import { AssertionEngine, AuctionState } from './AssertionEngine';
import hre from "hardhat";

export interface TestResult {
  setupData: SetupData;
  interactionData: InteractionData;
  auction: any;
  auctionedToken: any;
  currencyToken: any;
  finalState: AuctionState;
  success: boolean;
}


export interface EventData {
  type: 'bid' | 'groupBid' | 'action' | 'checkpoint';
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
    const setupData = this.schemaValidator.loadTestInstance('setup', setupFilename) as SetupData;
    const interactionData = this.schemaValidator.loadTestInstance('interaction', interactionFilename) as InteractionData;
    
    console.log('✅ Schema validation passed');
    
    // PHASE 1: Setup the auction environment
    console.log('🏗️  Phase 1: Setting up auction environment...');
    const auction = await this.deployer.createAuction(setupData);
    await this.deployer.setupBalances(setupData);
    
    console.log(`   🏛️  Auction deployed: ${await auction.getAddress()}`);
    
    // PHASE 2: Execute interactions on the configured auction
    console.log('🎯 Phase 2: Executing interaction scenario...');
    const auctionedToken = this.deployer.getTokenByName(setupData.auctionParameters.auctionedToken);
    const currencyToken = setupData.auctionParameters.currency === '0x0000000000000000000000000000000000000000' ? null : this.deployer.getTokenByName(setupData.auctionParameters.currency);
    const bidSimulator = new BidSimulator(auction, currencyToken || null);
    const assertionEngine = new AssertionEngine(auction, auctionedToken || null, currencyToken || null);
    
    // Setup labels and execute the interaction scenario
    await bidSimulator.setupLabels(interactionData);
    
    // Execute bids and actions with integrated checkpoint validation
    await this.executeWithCheckpoints(bidSimulator, assertionEngine, interactionData, interactionData.timeBase);
    
    console.log('   💰 Bids executed and checkpoints validated successfully');
    
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
   * Execute bids and actions with integrated checkpoint validation
   * Checkpoints are validated at their specific blocks during execution
   * Multiple events in the same block are executed together
   */
  async executeWithCheckpoints(
    bidSimulator: BidSimulator, 
    assertionEngine: AssertionEngine, 
    interactionData: InteractionData, 
    timeBase: string
  ): Promise<void> {
    // Collect all events (bids, actions, checkpoints) and sort by block
    const allEvents: EventData[] = [];
    
    // Add bids
    if (interactionData.namedBidders) {
      interactionData.namedBidders.forEach(bidder => {
        bidder.bids.forEach(bid => {
          allEvents.push({
            type: 'bid',
            atBlock: bid.atBlock,
            data: { bidder: bidder.address, ...bid }
          });
        });
      });
    }
    
    // Add group bids
    if (interactionData.groups) {
      interactionData.groups.forEach(group => {
        // Note: We need to access the groupBidders from the bidSimulator
        // This is a bit of a hack since we don't have direct access to the private property
        // In a real implementation, we'd want to expose this through a public method
        for (let round = 0; round < group.rounds; round++) {
          for (let i = 0; i < group.count; i++) {
            const blockOffset = group.startOffsetBlocks + 
              (round * (group.rotationIntervalBlocks + group.betweenRoundsBlocks)) +
              (i * group.rotationIntervalBlocks);
            
            allEvents.push({
              type: 'groupBid',
              atBlock: blockOffset,
              data: { group, ...group }
            });
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
              type: 'action',
              atBlock: interaction.atBlock,
              data: { actionType: action.type, ...interaction }
            });
          });
        });
      });
    }
    
    // Add checkpoints
    if (interactionData.checkpoints) {
      interactionData.checkpoints.forEach(checkpoint => {
        allEvents.push({
          type: 'checkpoint',
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
      // Within the same block, execute queries/checkpoints before transactions
      const queryTypes = ['checkpoint'];
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
        
        // Execute the event
        switch (event.type) {
          case 'bid':
            await bidSimulator.executeBid(event.data);
            break;
          case 'groupBid':
            await bidSimulator.executeBid(event.data);
            break;
          case 'action':
            if (event.data.actionType === 'Transfer') {
              await bidSimulator.executeTransfers([[event.data]]);
            } else if (event.data.actionType === 'AdminAction') {
              await bidSimulator.executeAdminActions([[event.data]]);
            }
            break;
          case 'checkpoint':
            console.log(`         🔍 Validating checkpoint: ${event.data.reason}`);
            await assertionEngine.validateAssertion(event.data.assert);
            console.log(`         ✅ Checkpoint validated`);
            break;
        }
      }
    }
  }

}
