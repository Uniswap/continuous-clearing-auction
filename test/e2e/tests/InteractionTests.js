const { expect } = require('chai');
const { ethers, network } = require('hardhat');
const TestRunner = require('../src/TestRunner');
const AuctionDeployer = require('../src/AuctionDeployer');
const BidSimulator = require('../src/BidSimulator');
const AssertionEngine = require('../src/AssertionEngine');

describe('Auction Interaction Tests', function() {
  let testRunner;
  let deployer;
  let bidSimulator;
  let assertionEngine;

  before(async function() {
    testRunner = new TestRunner();
    deployer = new AuctionDeployer();
  });

  it('Should execute setup01 + interaction01 combination successfully', async function() {
    // Load test data - setup defines the auction, interaction defines the behavior
    const setupData = testRunner.loadTestInstance('setup', 'setup01.json');
    const interactionData = testRunner.loadTestInstance('interaction', 'interaction01.json');
    
    // Validate both schemas
    testRunner.validateSetup(setupData);
    testRunner.validateInteraction(interactionData);
    
    // PHASE 1: Setup the auction environment
    const token = await deployer.deployToken(setupData.token);
    await deployer.setupBalances(setupData);
    const auction = await deployer.createAuction(setupData, token);
    
    // PHASE 2: Execute interactions on the configured auction
    bidSimulator = new BidSimulator(auction, token, null); // currency will be ETH
    assertionEngine = new AssertionEngine(auction, token, null);
    
    // Setup labels and execute the interaction scenario
    await bidSimulator.setupLabels(setupData, interactionData);
    await bidSimulator.executeBids(interactionData, interactionData.timeBase);
    await bidSimulator.executeActions(interactionData, interactionData.timeBase);
    
    // Validate checkpoints defined in the interaction
    await assertionEngine.validateCheckpoints(interactionData, interactionData.timeBase);
    
    // Get final state
    const finalState = await assertionEngine.getAuctionState();
    expect(finalState.isGraduated).to.be.a('boolean');
  });

  it('Should handle named bidders correctly', async function() {
    const setupData = testRunner.loadTestInstance('setup', 'setup01.json');
    const interactionData = testRunner.loadTestInstance('interaction', 'interaction01.json');
    
    const token = await deployer.deployToken(setupData.token);
    await deployer.setupBalances(setupData);
    const auction = await deployer.createAuction(setupData, token);
    
    bidSimulator = new BidSimulator(auction, token, null);
    await bidSimulator.setupLabels(setupData, interactionData);
    
    // Verify named bidder is set up correctly
    const namedBidder = interactionData.namedBidders[0];
    expect(bidSimulator.labelMap.get(namedBidder.label)).to.equal(namedBidder.address);
  });

  it('Should handle group bidders correctly', async function() {
    const setupData = testRunner.loadTestInstance('setup', 'setup01.json');
    const interactionData = testRunner.loadTestInstance('interaction', 'interaction01.json');
    
    const token = await deployer.deployToken(setupData.token);
    await deployer.setupBalances(setupData);
    const auction = await deployer.createAuction(setupData, token);
    
    bidSimulator = new BidSimulator(auction, token, null);
    await bidSimulator.setupLabels(setupData, interactionData);
    
    // Verify group bidders are generated
    const group = interactionData.groups[0];
    const groupBidders = bidSimulator.groupBidders.get(group.labelPrefix);
    expect(groupBidders).to.have.lengthOf(group.count);
  });

  it('Should validate checkpoints correctly', async function() {
    const setupData = testRunner.loadTestInstance('setup', 'setup01.json');
    const interactionData = testRunner.loadTestInstance('interaction', 'interaction01.json');
    
    const token = await deployer.deployToken(setupData.token);
    await deployer.setupBalances(setupData);
    const auction = await deployer.createAuction(setupData, token);
    
    assertionEngine = new AssertionEngine(auction, token, null);
    
    // Execute the full interaction
    bidSimulator = new BidSimulator(auction, token, null);
    await bidSimulator.setupLabels(setupData, interactionData);
    await bidSimulator.executeBids(interactionData, interactionData.timeBase);
    
    // Validate checkpoints
    await assertionEngine.validateCheckpoints(interactionData, interactionData.timeBase);
  });

  it('Should handle invalid interaction data', async function() {
    const invalidInteraction = {
      timeBase: "invalidBase",
      namedBidders: [
        {
          address: "0x1111111111111111111111111111111111111111",
          bids: [
            {
              atBlock: -1, // Invalid negative block
              amount: { side: "input", type: "raw", value: "1000000000000000000" },
              price: { type: "tick", value: 120 }
            }
          ]
        }
      ]
    };

    expect(() => {
      testRunner.validateInteraction(invalidInteraction);
    }).to.throw('Interaction validation failed');
  });
});
