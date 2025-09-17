const { expect } = require('chai');
const { ethers } = require('hardhat');
const TestCombinationRunner = require('../src/TestCombinationRunner');

describe('E2E Tests', function() {
  let runner;

  before(async function() {
    console.log('🔍 Test: ethers available?', !!ethers);
    console.log('🔍 Test: hre.ethers available?', !!hre.ethers);
    runner = new TestCombinationRunner(hre, ethers);
  });

  it('should run simple setup and interaction', async function() {
    const combinations = [
      { setup: 'simple-setup.json', interaction: 'simple-interaction.json' }
    ];
    
    console.log('🚀 TWAP Auction E2E Test Runner');
    console.log('================================');
    
    // Show available files
    const availableFiles = runner.getAvailableFiles();
    console.log('\n📁 Available files:');
    console.log('   Setup files:', availableFiles.setup.join(', '));
    console.log('   Interaction files:', availableFiles.interaction.join(', '));
    
    // Run the specified combinations
    console.log(`\n🎯 Running ${combinations.length} specified combinations...`);
    const results = await runner.runAllCombinations(combinations);
    
    // Summary
    const passed = results.filter(r => r.success).length;
    const failed = results.filter(r => !r.success).length;
    
    console.log('\n🏁 Final Summary:');
    console.log(`   Total combinations: ${results.length}`);
    console.log(`   ✅ Passed: ${passed}`);
    console.log(`   ❌ Failed: ${failed}`);
    
    if (failed > 0) {
      console.log('\n❌ Failed combinations:');
      results.filter(r => !r.success).forEach(r => {
        console.log(`   - ${r.setupFile} + ${r.interactionFile}: ${r.error}`);
      });
      throw new Error(`${failed} test(s) failed`);
    } else {
      console.log('\n🎉 All tests passed!');
    }
  });
});
