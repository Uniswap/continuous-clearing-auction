#!/usr/bin/env node

const hre = require('hardhat');
const TestCombinationRunner = require('../../test/e2e/src/TestCombinationRunner');

// Define the combinations you want to run
const COMBINATIONS_TO_RUN = [
  { setup: 'simple-setup.json', interaction: 'simple-interaction.json' }
  // Add more combinations here as you create them:
  // { setup: 'setup02.json', interaction: 'interaction01.json' },
  // { setup: 'setup01.json', interaction: 'interaction02.json' },
];

async function main() {
  const runner = new TestCombinationRunner(hre);
  
  console.log('🚀 TWAP Auction E2E Test Runner');
  console.log('================================');
  
  // Show available files
  const availableFiles = runner.getAvailableFiles();
  console.log('\n📁 Available files:');
  console.log('   Setup files:', availableFiles.setup.join(', '));
  console.log('   Interaction files:', availableFiles.interaction.join(', '));
  
  // Run the specified combinations
  console.log(`\n🎯 Running ${COMBINATIONS_TO_RUN.length} specified combinations...`);
  const results = await runner.runAllCombinations(COMBINATIONS_TO_RUN);
  
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
    process.exit(1);
  } else {
    console.log('\n🎉 All tests passed!');
    process.exit(0);
  }
}

// Handle command line arguments
if (process.argv.includes('--all')) {
  // Run all possible combinations
  async function runAll() {
    const runner = new TestCombinationRunner(hre);
    const results = await runner.runAllPossibleCombinations();
    
    const passed = results.filter(r => r.success).length;
    const failed = results.filter(r => !r.success).length;
    
    if (failed > 0) {
      process.exit(1);
    } else {
      process.exit(0);
    }
  }
  runAll();
} else {
  main();
}
