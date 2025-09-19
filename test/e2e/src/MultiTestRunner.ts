import { SingleTestRunner, TestResult } from './SingleTestRunner';
import { TestInstance } from './SchemaValidator';

export interface CombinationResult {
  success: boolean;
  result?: TestResult;
  error?: string;
  setupFile: string;
  interactionFile: string;
}

export interface AvailableFiles {
  setup: string[];
  interaction: string[];
}

export interface Combination {
  setup: string;
  interaction: string;
}

export class MultiTestRunner {
  private singleTestRunner: SingleTestRunner;

  constructor() {
    this.singleTestRunner = new SingleTestRunner();
  }

  /**
   * Run a specific setup + interaction combination
   */
  async runCombination(setupFile: string, interactionFile: string): Promise<CombinationResult> {
    console.log(`\n🎯 Running combination: ${setupFile} + ${interactionFile}`);
    
    try {
      const result = await this.singleTestRunner.runCombinedTest(setupFile, interactionFile);
      console.log(`✅ ${setupFile} + ${interactionFile} - PASSED`);
      return { success: true, result, setupFile, interactionFile };
    } catch (error: unknown) {
      console.error(`❌ ${setupFile} + ${interactionFile} - FAILED`);
      const errorMessage = error instanceof Error ? error.message : String(error);
      console.error(`   Error: ${errorMessage}`);
      return { success: false, error: errorMessage, setupFile, interactionFile };
    }
  }

  /**
   * Run all predefined combinations
   */
  async runAllCombinations(combinations: Combination[]): Promise<CombinationResult[]> {
    console.log(`\n🧪 Running ${combinations.length} test combinations...`);
    
    const results: CombinationResult[] = [];
    let passed = 0;
    let failed = 0;

    for (const combo of combinations) {
      const result = await this.runCombination(combo.setup, combo.interaction);
      results.push(result);
      
      if (result.success) {
        passed++;
      } else {
        failed++;
      }
    }

    console.log(`\n📊 Test Results:`);
    console.log(`   ✅ Passed: ${passed}`);
    console.log(`   ❌ Failed: ${failed}`);
    console.log(`   📈 Success Rate: ${((passed / combinations.length) * 100).toFixed(1)}%`);

    return results;
  }

  /**
   * Get all available setup and interaction files
   */
  getAvailableFiles(): AvailableFiles {
    const setupFiles = this.singleTestRunner['schemaValidator'].getAllTestInstances('setup');
    const interactionFiles = this.singleTestRunner['schemaValidator'].getAllTestInstances('interaction');
    
    return {
      setup: setupFiles.map((f: TestInstance) => f.filename),
      interaction: interactionFiles.map((f: TestInstance) => f.filename)
    };
  }
}
