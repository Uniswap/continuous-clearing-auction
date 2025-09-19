#!/usr/bin/env node

import { MultiTestRunner, CombinationResult } from './MultiTestRunner';
import { TestInstance } from './SchemaValidator';

// Define the combinations you want to run
const COMBINATIONS_TO_RUN = [
  { setup: 'SimpleSetup.ts', interaction: 'SimpleInteraction.ts' }
  // TODO: Add more combinations here as they are created:
  // { setup: 'setup02.json', interaction: 'interaction02.json' },
  // { setup: 'setup03.json', interaction: 'interaction01.json' },
];

interface CombinationToRun {
  setup: string;
  interaction: string;
}

interface AvailableFiles {
  setup: string[];
  interaction: string[];
}

class E2ECliRunner {
  private runner: MultiTestRunner;

  constructor() {
    this.runner = new MultiTestRunner();
  }

  getAvailableFiles(): AvailableFiles {
    const setupInstances = this.runner['singleTestRunner']['schemaValidator'].getAllTestInstances('setup');
    const interactionInstances = this.runner['singleTestRunner']['schemaValidator'].getAllTestInstances('interaction');
    
    return {
      setup: setupInstances.map((instance: TestInstance) => instance.filename),
      interaction: interactionInstances.map((instance: TestInstance) => instance.filename)
    };
  }

  async runAllCombinations(combinations: CombinationToRun[]): Promise<CombinationResult[]> {
    const results: CombinationResult[] = [];
    
    for (const combination of combinations) {
      try {
        console.log(`\n🧪 Running: ${combination.setup} + ${combination.interaction}`);
        const result = await this.runner.runCombination(combination.setup, combination.interaction);
        results.push(result);
        console.log(`✅ Success: ${combination.setup} + ${combination.interaction}`);
      } catch (error: unknown) {
        console.error(`❌ Failed: ${combination.setup} + ${combination.interaction}`);
        const errorMessage = error instanceof Error ? error.message : String(error);
        console.error(`   Error: ${errorMessage}`);
        results.push({
          setupFile: combination.setup,
          interactionFile: combination.interaction,
          success: false,
          error: errorMessage
        });
      }
    }
    
    return results;
  }
}

async function main(): Promise<void> {
  const runner = new E2ECliRunner();
  
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
  console.log('  npx ts-node test/e2e/src/CombinationRunner.ts');
  console.log('  npx ts-node test/e2e/src/CombinationRunner.ts --setup <setup-file> --interaction <interaction-file>');
  console.log('\n📁 Examples:');
  console.log('  npx ts-node test/e2e/src/CombinationRunner.ts');
  console.log('  npx ts-node test/e2e/src/CombinationRunner.ts --setup SimpleSetup.ts --interaction SimpleInteraction.ts');
  console.log('\n💡 Note: Only run compatible setup/interaction combinations!');
  process.exit(0);
}

main().catch((error) => {
  console.error('Fatal error:', error);
  process.exit(1);
});
