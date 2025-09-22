import { MultiTestRunner } from '../src/MultiTestRunner';
import { simpleSetup } from '../instances/setup/SimpleSetup';
import { simpleInteraction } from '../instances/interaction/SimpleInteraction';
import hre from "hardhat";

describe('E2E Tests', function() {
  let runner: MultiTestRunner;

  before(async function() {
    console.log('🔍 Test: hre.ethers available?', !!hre.ethers);
    runner = new MultiTestRunner();
  });

  it('should run simple setup and interaction', async function() {
    const combinations = [
      { setup: simpleSetup, interaction: simpleInteraction }
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
        console.log(`   - ${r.setupName} + ${r.interactionName}: ${r.error}`);
      });
      throw new Error(`${failed} test(s) failed`);
    } else {
      console.log('\n🎉 All tests passed!');
    }
  });
});
