import { SingleTestRunner, TestResult } from "./SingleTestRunner";
import { TestInstance } from "./SchemaValidator";
import { TestSetupData } from "../schemas/TestSetupSchema";
import { TestInteractionData } from "../schemas/TestInteractionSchema";
import { LOG_PREFIXES } from "./constants";

export interface CombinationResult {
  success: boolean;
  result?: TestResult;
  error?: string;
  setupName: string;
  interactionName: string;
}

export interface AvailableFiles {
  setup: string[];
  interaction: string[];
}

export interface Combination {
  setup: TestSetupData;
  interaction: TestInteractionData;
}

export class MultiTestRunner {
  private singleTestRunner: SingleTestRunner;

  constructor() {
    this.singleTestRunner = new SingleTestRunner();
  }

  /**
   * Run a specific setup + interaction combination
   */
  async runCombination(setupData: TestSetupData, interactionData: TestInteractionData): Promise<CombinationResult> {
    const setupName = setupData.name;
    const interactionName = interactionData.name;
    console.log(LOG_PREFIXES.INFO, "Running combination:", setupName, "+", interactionName);

    try {
      const result = await this.singleTestRunner.runFullTest(setupData, interactionData);
      console.log(LOG_PREFIXES.SUCCESS, setupName, "+", interactionName, "- PASSED");
      return { success: true, result, setupName, interactionName };
    } catch (error: unknown) {
      console.error(LOG_PREFIXES.ERROR, setupName, "+", interactionName, "- FAILED");
      const errorMessage = error instanceof Error ? error.message : String(error);
      console.error(LOG_PREFIXES.ERROR, "Error:", errorMessage);
      return { success: false, error: errorMessage, setupName, interactionName };
    }
  }

  /**
   * Run all predefined combinations
   */
  async runAllCombinations(combinations: Combination[]): Promise<CombinationResult[]> {
    console.log(LOG_PREFIXES.INFO, "Running", combinations.length, "test combinations...");

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

    console.log(LOG_PREFIXES.INFO, "Test Results:");
    console.log(LOG_PREFIXES.SUCCESS, "Passed:", passed);
    console.log(LOG_PREFIXES.ERROR, "Failed:", failed);
    console.log(LOG_PREFIXES.INFO, "Success Rate:", ((passed / combinations.length) * 100).toFixed(1) + "%");

    return results;
  }

  /**
   * Get all available setup and interaction files
   */
  getAvailableFiles(): AvailableFiles {
    const setupFiles = this.singleTestRunner["schemaValidator"].getAllTestInstances("setup");
    const interactionFiles = this.singleTestRunner["schemaValidator"].getAllTestInstances("interaction");

    return {
      setup: setupFiles.map((f: TestInstance) => f.filename),
      interaction: interactionFiles.map((f: TestInstance) => f.filename),
    };
  }
}
