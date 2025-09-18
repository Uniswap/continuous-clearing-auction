const TestRunner = require('./TestRunner');
const AuctionDeployer = require('./AuctionDeployer');
const BidSimulator = require('./BidSimulator');
const AssertionEngine = require('./AssertionEngine');

class CombinedTestRunner {
  constructor(hre, ethers) {
    this.hre = hre;
    this.ethers = ethers;
    this.network = hre.network;
    this.testRunner = new TestRunner();
    this.deployer = new AuctionDeployer(hre, ethers);
  }

  /**
   * Runs a complete test combining setup and interaction schemas
   * @param {string} setupFilename - Name of the setup JSON file
   * @param {string} interactionFilename - Name of the interaction JSON file
   * @returns {Object} Test results and final state
   */
  async runCombinedTest(setupFilename, interactionFilename) {
    console.log(`\n🧪 Running combined test: ${setupFilename} + ${interactionFilename}`);
    
    // Load and validate both schemas
    const setupData = this.testRunner.loadTestInstance('setup', setupFilename);
    const interactionData = this.testRunner.loadTestInstance('interaction', interactionFilename);
    
    this.testRunner.validateSetup(setupData);
    this.testRunner.validateInteraction(interactionData);
    
    console.log('✅ Schema validation passed');
    
    // PHASE 1: Setup the auction environment
    console.log('🏗️  Phase 1: Setting up auction environment...');
    const auction = await this.deployer.createAuction(setupData);
    await this.deployer.setupBalances(setupData);
    
    console.log(`   🏛️  Auction deployed: ${await auction.getAddress()}`);
    
    // PHASE 2: Execute interactions on the configured auction
    console.log('🎯 Phase 2: Executing interaction scenario...');
    const auctionedToken = this.deployer.getTokenByName(setupData.auctionParameters.auctionedToken);
    const currencyToken = setupData.auctionParameters.currency === 'ETH' ? null : this.deployer.getTokenByName(setupData.auctionParameters.currency);
    const bidSimulator = new BidSimulator(this.hre, auction, auctionedToken, currencyToken);
    const assertionEngine = new AssertionEngine(auction, auctionedToken, currencyToken, this.ethers);
    
    // Setup labels and execute the interaction scenario
    await bidSimulator.setupLabels(setupData, interactionData);
    
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
      auctionedToken,
      currencyToken,
      finalState,
      success: true
    };
  }

  /**
   * Execute bids and actions with integrated checkpoint validation
   * Checkpoints are validated at their specific blocks during execution
   * Multiple events in the same block are executed together
   */
  async executeWithCheckpoints(bidSimulator, assertionEngine, interactionData, timeBase) {
    // Collect all events (bids, actions, checkpoints) and sort by block
    const allEvents = [];
    
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
        const bidders = bidSimulator.groupBidders.get(group.labelPrefix);
        for (let round = 0; round < group.rounds; round++) {
          for (let i = 0; i < group.count; i++) {
            const bidder = bidders[i];
            const blockOffset = group.startOffsetBlocks + 
              (round * (group.rotationIntervalBlocks + group.betweenRoundsBlocks)) +
              (i * group.rotationIntervalBlocks);
            
            allEvents.push({
              type: 'groupBid',
              atBlock: blockOffset,
              data: { bidder, group, ...group }
            });
          }
        }
      });
    }
    
    // Add actions
    if (interactionData.actions) {
      interactionData.actions.forEach(action => {
        action.interactions.forEach(interactionGroup => {
          interactionGroup.forEach(interaction => {
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
    const eventsByBlock = {};
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

  /**
   * Runs all available setup/interaction combinations
   */
  async runAllCombinations() {
    const setupInstances = this.testRunner.getAllTestInstances('setup');
    const interactionInstances = this.testRunner.getAllTestInstances('interaction');
    
    const results = [];
    
    for (const setup of setupInstances) {
      for (const interaction of interactionInstances) {
        try {
          const result = await this.runCombinedTest(setup.filename, interaction.filename);
          results.push({
            setup: setup.filename,
            interaction: interaction.filename,
            success: true,
            result
          });
        } catch (error) {
          console.error(`❌ Test failed: ${setup.filename} + ${interaction.filename}`);
          console.error(error.message);
          results.push({
            setup: setup.filename,
            interaction: interaction.filename,
            success: false,
            error: error.message
          });
        }
      }
    }
    
    return results;
  }

  /**
   * Validates that a setup and interaction are compatible
   */
  validateCompatibility(setupData, interactionData) {
    // Check if interaction references match setup
    const setupAddresses = new Set([
      setupData.auctionParameters.currency,
      setupData.auctionParameters.tokensRecipient,
      setupData.auctionParameters.fundsRecipient,
      setupData.auctionParameters.validationHook
    ]);
    
    // Validate that interaction addresses exist in setup
    if (interactionData.namedBidders) {
      interactionData.namedBidders.forEach(bidder => {
        if (!setupAddresses.has(bidder.address)) {
          console.warn(`⚠️  Bidder address ${bidder.address} not found in setup`);
        }
      });
    }
    
    return true;
  }
}

module.exports = CombinedTestRunner;
