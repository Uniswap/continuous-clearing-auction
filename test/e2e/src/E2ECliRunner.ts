#!/usr/bin/env node

import { MultiTestRunner, CombinationResult } from "./MultiTestRunner";
import { TestInstance } from "./SchemaValidator";
import { TestSetupData } from "../schemas/TestSetupSchema";
import { TestInteractionData } from "../schemas/TestInteractionSchema";
import { LOG_PREFIXES, ERROR_MESSAGES, SETUP, INTERACTION } from "./constants";
import * as fs from "fs";
import * as path from "path";

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
   * Converts a test name to PascalCase filename.
   * Examples: "simple" → "SimpleSetup", "erc20" → "ERC20Setup", "extended" → "ExtendedSetup"
   */
  private toFileName(testName: string, type: "setup" | "interaction"): string {
    const suffix = type === "setup" ? "Setup" : "Interaction";
    // Capitalize first letter
    const pascalName = testName.charAt(0).toUpperCase() + testName.slice(1);
    return pascalName + suffix;
  }

  /**
   * Gets available test names by scanning the instances directory.
   * @returns Array of test names (without Setup/Interaction suffix)
   */
  getAvailableTestNames(): string[] {
    const setupDir = path.join(__dirname, "../instances/setup");
    if (!fs.existsSync(setupDir)) return [];

    const files = fs.readdirSync(setupDir);
    return files.filter((file) => file.endsWith(".ts")).map((file) => file.replace(/Setup\.ts$/, "").toLowerCase());
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
 * Loads test combinations from CLI arguments or returns all available tests.
 * Test names can be provided without the "Setup" suffix (e.g., "simple", "extended").
 * @param runner - The E2ECliRunner instance
 * @returns Array of combinations to run
 */
async function loadCombinationsFromArgs(runner: E2ECliRunner): Promise<CombinationToRun[]> {
  const args = process.argv.slice(2).filter((arg) => !arg.startsWith("-")); // Filter out flags
  const availableTests = runner.getAvailableTestNames();

  if (args.length === 0) {
    // No arguments provided, run all available tests
    console.log("📋 No arguments provided, running all", availableTests.length, "available tests");
    const combinations: CombinationToRun[] = [];

    for (const testName of availableTests) {
      const setupFile = runner["toFileName"](testName, "setup");
      const interactionFile = runner["toFileName"](testName, "interaction");

      try {
        const setup = loadInstanceFromFile(setupFile, SETUP);
        const interaction = loadInstanceFromFile(interactionFile, INTERACTION);
        combinations.push({ setup, interaction });
      } catch (error) {
        console.warn(LOG_PREFIXES.WARNING, `Skipping ${testName}: ${error}`);
      }
    }

    return combinations;
  }

  const combinations: CombinationToRun[] = [];

  for (const testName of args) {
    const normalizedName = testName.toLowerCase();

    // Convert test name to file names
    const setupFile = runner["toFileName"](normalizedName, "setup");
    const interactionFile = runner["toFileName"](normalizedName, "interaction");

    try {
      const setup = loadInstanceFromFile(setupFile, SETUP);
      const interaction = loadInstanceFromFile(interactionFile, INTERACTION);
      combinations.push({ setup, interaction });
      console.log(LOG_PREFIXES.SUCCESS, "Loaded test:", testName, "→", setup.name, "+", interaction.name);
    } catch (error) {
      console.error(LOG_PREFIXES.ERROR, "Failed to load test:", testName);
      console.error(LOG_PREFIXES.ERROR, "Error:", error);
      console.log("\n📝 Available tests:", availableTests.join(", "));
      process.exit(1);
    }
  }

  return combinations;
}

/**
 * Loads a TypeScript instance from a file using the SchemaValidator.
 * @param fileName - The file name to load (e.g., "SimpleSetup", "ExtendedInteraction")
 * @param type - The type of instance to load ("setup" or "interaction")
 * @returns The loaded test instance data
 * @throws Error if the file cannot be loaded or no instance is found
 */
function loadInstanceFromFile(fileName: string, type: "setup"): TestSetupData;
function loadInstanceFromFile(fileName: string, type: "interaction"): TestInteractionData;
function loadInstanceFromFile(fileName: string, type: "setup" | "interaction"): TestSetupData | TestInteractionData {
  const { SchemaValidator } = require("./SchemaValidator");
  const validator = new SchemaValidator();
  return validator.loadTestInstance(type, fileName);
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

  // Show available tests
  const availableTests = runner.getAvailableTestNames();
  console.log("\n📝 Available tests:", availableTests.join(", "));

  // Load combinations from CLI arguments or use all available
  const combinationsToRun = await loadCombinationsFromArgs(runner);

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
  console.log("\n📖 E2E CLI Test Runner");
  console.log("======================\n");
  console.log("Usage:");
  console.log("  npm run e2e:run [test1] [test2] ...");
  console.log("  npm run e2e:run                    (runs all tests)\n");
  console.log("Examples:");
  console.log("  npm run e2e:run extended              (run just Extended test)");
  console.log("  npm run e2e:run simple erc20       (run Simple and ERC20 tests)");
  console.log("  npm run e2e:run                    (run all available tests)");
  console.log("  npm run e2e:run extended > log.txt    (save output to file)\n");
  console.log("Test names are auto-discovered from test/e2e/instances/");
  console.log("Each test loads matching Setup + Interaction files.");
  process.exit(0);
}

main().catch((error) => {
  console.error("Fatal error:", error);
  process.exit(1);
});
