import { SingleTestRunner, TestResult } from './SingleTestRunner';

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
  private hre: any;
  private ethers: any;
  private singleTestRunner: SingleTestRunner;

  constructor(hre: any, ethers: any) {
    this.hre = hre;
    this.ethers = ethers;
    this.singleTestRunner = new SingleTestRunner(hre);
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
    } catch (error: any) {
      console.error(`❌ ${setupFile} + ${interactionFile} - FAILED`);
      console.error(`   Error: ${error.message}`);
      return { success: false, error: error.message, setupFile, interactionFile };
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
      setup: setupFiles.map(f => f.filename),
      interaction: interactionFiles.map(f => f.filename)
    };
  }

  /**
   * Generate all possible combinations of setup + interaction files
   */
  generateAllCombinations(): Combination[] {
    const files = this.getAvailableFiles();
    const combinations: Combination[] = [];
    
    for (const setup of files.setup) {
      for (const interaction of files.interaction) {
        combinations.push({ setup, interaction });
      }
    }
    
    return combinations;
  }

  /**
   * Run all possible combinations
   */
  async runAllPossibleCombinations(): Promise<CombinationResult[]> {
    const combinations = this.generateAllCombinations();
    return await this.runAllCombinations(combinations);
  }
}
