const { expect } = require('chai');
const { ethers, network } = require('hardhat');
const CombinedTestRunner = require('../src/CombinedTestRunner');

describe('Combined Setup + Interaction Tests', function() {
  let combinedRunner;

  before(async function() {
    combinedRunner = new CombinedTestRunner();
  });

  // Dynamic test generation for all setup/interaction combinations
  const testCombinations = [
    { setup: 'setup01.json', interaction: 'interaction01.json' }
    // Add more combinations here as you create them
  ];

  testCombinations.forEach(({ setup, interaction }) => {
    it(`Should run ${setup} + ${interaction} combination`, async function() {
      const result = await combinedRunner.runCombinedTest(setup, interaction);
      
      expect(result.success).to.be.true;
      expect(result.auction).to.not.be.undefined;
      expect(result.token).to.not.be.undefined;
      expect(result.finalState).to.be.an('object');
      
      // Verify checkpoints were validated
      expect(result.finalState).to.have.property('currentBlock');
    });
  });

  it('Should validate setup and interaction compatibility', async function() {
    const setupData = combinedRunner.testRunner.loadTestInstance('setup', 'setup01.json');
    const interactionData = combinedRunner.testRunner.loadTestInstance('interaction', 'interaction01.json');
    
    expect(() => {
      combinedRunner.validateCompatibility(setupData, interactionData);
    }).to.not.throw();
  });

  it('Should handle multiple setup/interaction combinations', async function() {
    // This test would run all available combinations
    // For now, just test that the method exists and works
    const results = await combinedRunner.runAllCombinations();
    
    expect(results).to.be.an('array');
    expect(results.length).to.be.greaterThan(0);
    
    // Check that at least one combination succeeded
    const successfulTests = results.filter(r => r.success);
    expect(successfulTests.length).to.be.greaterThan(0);
  });

  it('Should properly sequence setup and interaction phases', async function() {
    const result = await combinedRunner.runCombinedTest('setup01.json', 'interaction01.json');
    
    // Verify the auction was properly set up
    const auction = result.auction;
    const setupData = result.setupData;
    
    // Check that auction parameters match setup
    expect(await auction.currency()).to.equal(setupData.auctionParameters.currency);
    expect(await auction.tokensRecipient()).to.equal(setupData.auctionParameters.tokensRecipient);
    expect(await auction.fundsRecipient()).to.equal(setupData.auctionParameters.fundsRecipient);
    
    // Verify interaction was executed
    const finalState = result.finalState;
    expect(finalState).to.have.property('currentBlock');
    expect(finalState).to.have.property('isGraduated');
  });

  it('Should handle interaction timing relative to auction start', async function() {
    const result = await combinedRunner.runCombinedTest('setup01.json', 'interaction01.json');
    
    const interactionData = result.interactionData;
    const finalState = result.finalState;
    
    // Verify that interactions were executed at the correct blocks
    // relative to auction start (timeBase: "auctionStart")
    expect(finalState.currentBlock).to.be.a('number');
    
    // Check that the auction progressed through the interaction timeline
    if (interactionData.checkpoints) {
      const lastCheckpoint = interactionData.checkpoints[interactionData.checkpoints.length - 1];
      expect(finalState.currentBlock).to.be.at.least(lastCheckpoint.atBlock);
    }
  });
});
