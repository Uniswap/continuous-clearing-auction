#!/usr/bin/env node

const hre = require('hardhat');
const { ethers } = require('hardhat');
const TestCombinationRunner = require('./TestCombinationRunner');

// Define the combinations you want to run
const COMBINATIONS_TO_RUN = [
  { setup: 'simple-setup.json', interaction: 'simple-interaction.json' }
  // Add more combinations here as you create them:
  // { setup: 'setup02.json', interaction: 'interaction02.json' },
  // { setup: 'setup03.json', interaction: 'interaction01.json' },
];

async function main() {
  const runner = new TestCombinationRunner(hre, ethers);
  
  console.log('🚀 TWAP Auction E2E Test Runner');
  console.log('================================');
  
  // Show available files
  const availableFiles = runner.getAvailableFiles();
  console.log('\n📁 Available files:');
  console.log('   Setup files:', availableFiles.setup.join(', '));
  console.log('   Interaction files:', availableFiles.interaction.join(', '));
  
  // Check for command line arguments
  let combinationsToRun = COMBINATIONS_TO_RUN;
  
  // Parse command line arguments for specific combinations
  const args = process.argv.slice(2);
  if (args.length >= 2) {
    const setupIndex = args.indexOf('--setup');
    const interactionIndex = args.indexOf('--interaction');
    
    if (setupIndex !== -1 && interactionIndex !== -1 && 
        setupIndex + 1 < args.length && interactionIndex + 1 < args.length) {
      const setupFile = args[setupIndex + 1];
      const interactionFile = args[interactionIndex + 1];
      
      console.log(`\n🎯 Running specific combination: ${setupFile} + ${interactionFile}`);
      combinationsToRun = [{ setup: setupFile, interaction: interactionFile }];
    }
  }
  
  // Run the specified combinations
  console.log(`\n🎯 Running ${combinationsToRun.length} specified combinations...`);
  const results = await runner.runAllCombinations(combinationsToRun);
  
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

// Show usage information
if (process.argv.includes('--help') || process.argv.includes('-h')) {
  console.log('\n📖 Usage:');
  console.log('  node test/e2e/src/CombinationRunner.js');
  console.log('  node test/e2e/src/CombinationRunner.js --setup <setup-file> --interaction <interaction-file>');
  console.log('\n📁 Examples:');
  console.log('  node test/e2e/src/CombinationRunner.js');
  console.log('  node test/e2e/src/CombinationRunner.js --setup simple-setup.json --interaction simple-interaction.json');
  console.log('\n💡 Note: Only run compatible setup/interaction combinations!');
  process.exit(0);
}

main();
