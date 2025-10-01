#!/usr/bin/env node

import { MultiTestRunner, CombinationResult } from "./MultiTestRunner";
import { TestInstance } from "./SchemaValidator";
import { TestSetupData } from "../schemas/TestSetupSchema";
import { TestInteractionData } from "../schemas/TestInteractionSchema";
import { LOG_PREFIXES, ERROR_MESSAGES, SETUP, INTERACTION } from "./constants";

// Import the actual TypeScript instances
import { simpleSetup } from "../instances/setup/SimpleSetup";
import { simpleInteraction } from "../instances/interaction/SimpleInteraction";
import { erc20Setup } from "../instances/setup/ERC20Setup";
import { erc20Interaction } from "../instances/interaction/ERC20Interaction";
import { advancedSetup } from "../instances/setup/AdvancedSetup";
import { advancedInteraction } from "../instances/interaction/AdvancedInteraction";

// Define the combinations to run
const COMBINATIONS_TO_RUN = [
  { setup: simpleSetup, interaction: simpleInteraction },
  { setup: erc20Setup, interaction: erc20Interaction },
  { setup: advancedSetup, interaction: advancedInteraction },
];

interface CombinationToRun {
  setup: TestSetupData;
  interaction: TestInteractionData;
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

  /**
   * Gets available setup and interaction files for testing.
   * @returns Object containing arrays of available setup and interaction files
   */
  getAvailableFiles(): AvailableFiles {
    const setupInstances = this.runner["singleTestRunner"]["schemaValidator"].getAllTestInstances(SETUP);
    const interactionInstances = this.runner["singleTestRunner"]["schemaValidator"].getAllTestInstances(INTERACTION);

    return {
      setup: setupInstances.map((instance: TestInstance) => instance.filename),
      interaction: interactionInstances.map((instance: TestInstance) => instance.filename),
    };
  }

  /**
   * Runs all specified test combinations.
   * @param combinations - Array of combinations to run
   * @returns Array of combination results
   */
  async runAllCombinations(combinations: CombinationToRun[]): Promise<CombinationResult[]> {
    const results: CombinationResult[] = [];

    for (const combination of combinations) {
      try {
        console.log(LOG_PREFIXES.INFO, "Running:", combination.setup.name, "+", combination.interaction.name);
        const result = await this.runner.runCombination(combination.setup, combination.interaction);
        results.push(result);
        console.log(LOG_PREFIXES.SUCCESS, "Success:", combination.setup.name, "+", combination.interaction.name);
      } catch (error: unknown) {
        console.error(LOG_PREFIXES.ERROR, "Failed:", combination.setup.name, "+", combination.interaction.name);
        const errorMessage = error instanceof Error ? error.message : String(error);
        console.error(LOG_PREFIXES.ERROR, "Error:", errorMessage);
        results.push({
          setupName: combination.setup.name,
          interactionName: combination.interaction.name,
          success: false,
          error: errorMessage,
        });
      }
    }

    return results;
  }
}

/**
 * Loads test combinations from CLI arguments or returns predefined combinations.
 * @returns Array of combinations to run
 */
async function loadCombinationsFromArgs(): Promise<CombinationToRun[]> {
  const args = process.argv.slice(2);

  if (args.length === 0) {
    // No arguments provided, use predefined combinations
    console.log("📋 No arguments provided, using predefined combinations");
    return COMBINATIONS_TO_RUN;
  }

  if (args.length % 2 !== 0) {
    console.error("❌ Error: Arguments must be provided in pairs (setup interaction)");
    console.log("Usage: npm run e2e:run [setup1 interaction1] [setup2 interaction2] ...");
    process.exit(1);
  }

  const combinations: CombinationToRun[] = [];

  for (let i = 0; i < args.length; i += 2) {
    const setupFile = args[i];
    const interactionFile = args[i + 1];

    try {
      const setupData = loadInstanceFromFile(setupFile, SETUP);
      const interactionData = loadInstanceFromFile(interactionFile, INTERACTION);

      combinations.push({
        setup: setupData,
        interaction: interactionData,
      });

      console.log(LOG_PREFIXES.SUCCESS, "Loaded:", setupData.name, "+", interactionData.name);
    } catch (error) {
      console.error(LOG_PREFIXES.ERROR, "Failed to load", setupFile, "+", interactionFile + ":", error);
      process.exit(1);
    }
  }

  return combinations;
}

/**
 * Loads a TypeScript instance from a file path.
 * @param filePath - The file path to load the instance from
 * @param type - The type of instance to load ("setup" or "interaction")
 * @returns The loaded test instance data
 * @throws Error if the file cannot be loaded or no instance is found
 */
function loadInstanceFromFile(filePath: string, type: "setup"): TestSetupData;
function loadInstanceFromFile(filePath: string, type: "interaction"): TestInteractionData;
function loadInstanceFromFile(filePath: string, type: "setup" | "interaction"): TestSetupData | TestInteractionData {
  // Remove .ts extension if present
  const cleanPath = filePath.replace(/\.ts$/, "");

  // Convert file path to require path
  const requirePath = `../instances/${type}/${cleanPath}`;

  try {
    // TODO: find a way to avoid require
    const module = require(requirePath);

    // Find the exported instance (should be the default export or a named export)
    const instance = module.default || module[cleanPath] || Object.values(module)[0];

    if (!instance) {
      throw new Error(ERROR_MESSAGES.NO_INSTANCE_FOUND(filePath));
    }

    return instance;
  } catch (error) {
    throw new Error(
      ERROR_MESSAGES.FAILED_TO_LOAD_FILE(filePath, error instanceof Error ? error.message : String(error)),
    );
  }
}

/**
 * Main entry point for the E2E test runner.
 * Loads test combinations from CLI arguments or uses predefined combinations,
 * runs all tests, and displays results with success/failure statistics.
 */
async function main(): Promise<void> {
  const runner = new E2ECliRunner();

  console.log(LOG_PREFIXES.RUN, "TWAP Auction E2E Test Runner");
  console.log("================================");

  // Show available files
  const availableFiles = runner.getAvailableFiles();
  console.log("\n", LOG_PREFIXES.FILES, "Available files:");
  console.log("   Setup files:", availableFiles.setup.join(", "));
  console.log("   Interaction files:", availableFiles.interaction.join(", "));

  // Load combinations from CLI arguments or use predefined ones
  const combinationsToRun = await loadCombinationsFromArgs();

  // Run the specified combinations
  console.log(LOG_PREFIXES.INFO, "Running", combinationsToRun.length, "specified combinations...");
  const results = await runner.runAllCombinations(combinationsToRun);

  // Summary
  const passed = results.filter((r) => r.success).length;
  const failed = results.filter((r) => !r.success).length;

  console.log(LOG_PREFIXES.INFO, "Final Summary:");
  console.log(LOG_PREFIXES.INFO, "Total combinations:", results.length);
  console.log(LOG_PREFIXES.SUCCESS, "Passed:", passed);
  console.log(LOG_PREFIXES.ERROR, "Failed:", failed);

  if (failed > 0) {
    console.log(LOG_PREFIXES.ERROR, "Failed combinations:");
    results
      .filter((r) => !r.success)
      .forEach((r) => {
        console.log(LOG_PREFIXES.ERROR, "-", r.setupName, "+", r.interactionName + ":", r.error);
      });
    process.exit(1);
  } else {
    console.log(LOG_PREFIXES.SUCCESS, "All tests passed!");
    process.exit(0);
  }
}

// Show usage information
if (process.argv.includes("--help") || process.argv.includes("-h")) {
  console.log("\n📖 Usage:");
  console.log("  npx ts-node test/e2e/src/CombinationRunner.ts");
  console.log("  npx ts-node test/e2e/src/CombinationRunner.ts --setup <setup-file> --interaction <interaction-file>");
  console.log("\n", LOG_PREFIXES.FILES, "Examples:");
  console.log("  npx ts-node test/e2e/src/CombinationRunner.ts");
  console.log(
    "  npx ts-node test/e2e/src/CombinationRunner.ts --setup SimpleSetup.ts --interaction SimpleInteraction.ts",
  );
  console.log("\n", LOG_PREFIXES.NOTE, " Note: Only run compatible setup/interaction combinations!");
  process.exit(0);
}

main().catch((error) => {
  console.error("Fatal error:", error);
  process.exit(1);
});
