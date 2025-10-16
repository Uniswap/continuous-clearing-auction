import * as fs from "fs";
import * as path from "path";
import { TestSetupData } from "../schemas/TestSetupSchema";
import { TestInteractionData } from "../schemas/TestInteractionSchema";
import { register } from "ts-node";
import { ERROR_MESSAGES, SETUP } from "./constants";

export interface TestInstance {
  filename: string;
  data: TestSetupData | TestInteractionData;
}

export class SchemaValidator {
  /**
   * Loads a test instance from a TypeScript file.
   * @param type - Type of test instance ("setup" or "interaction")
   * @param filename - Name of the file to load
   * @returns The loaded test instance data
   * @throws Error if file is not found or no export is found
   */
  loadTestInstance(type: "setup" | "interaction", filename: string): TestSetupData | TestInteractionData {
    // Only load TypeScript files
    if (filename.endsWith(".ts")) {
      const baseName = filename.replace(".ts", "");
      return this.loadTypeScriptInstance(type, baseName);
    } else {
      // Try to find .ts version
      const tsFilePath = path.join(__dirname, `../instances/${type}/${filename}.ts`);

      if (fs.existsSync(tsFilePath)) {
        return this.loadTypeScriptInstance(type, filename);
      } else {
        throw new Error(ERROR_MESSAGES.TYPESCRIPT_FILE_NOT_FOUND(tsFilePath));
      }
    }
  }

  /**
   * Converts a filename or test name to the expected export name (camelCase).
   * @param filename - The filename or test name to convert
   * @param type - The type of instance ("setup" or "interaction")
   * @returns The expected export name in camelCase format
   * @example
   * toExportName("SimpleSetup", "setup") → "simpleSetup"
   * toExportName("ERC20Setup", "setup") → "erc20Setup"
   * toExportName("simple", "setup") → "simpleSetup"
   * toExportName("extended", "setup") → "extendedSetup"
   */
  private toExportName(filename: string, type: "setup" | "interaction"): string {
    // Remove .ts extension if present
    let name = filename.replace(/\.ts$/, "");

    // If it doesn't end with Setup/Interaction, add it
    if (type === "setup" && !name.endsWith("Setup")) {
      // Capitalize first letter: "simple" → "Simple", "erc20" → "Erc20"
      name = name.charAt(0).toUpperCase() + name.slice(1) + "Setup";
    } else if (type === "interaction" && !name.endsWith("Interaction")) {
      name = name.charAt(0).toUpperCase() + name.slice(1) + "Interaction";
    }

    // Convert to camelCase: "SimpleSetup" → "simpleSetup", "ERC20Setup" → "erc20Setup"
    return name.charAt(0).toLowerCase() + name.slice(1);
  }

  /**
   * Loads a TypeScript instance from a file using ts-node.
   * @param type - Type of test instance ("setup" or "interaction")
   * @param filename - Name of the file to load
   * @returns The loaded test instance data
   * @throws Error if file is not found or no export is found
   */
  private loadTypeScriptInstance(type: "setup" | "interaction", filename: string): TestSetupData | TestInteractionData {
    let modulePath: string;
    try {
      if (type === SETUP) {
        // Use ts-node to load TypeScript files directly
        modulePath = path.join(__dirname, `../instances/setup/${filename}.ts`);
      } else {
        // Use ts-node to load TypeScript files directly
        modulePath = path.join(__dirname, `../instances/interaction/${filename}.ts`);
      }
      delete require.cache[modulePath];

      // Register ts-node
      register();

      // TODO: find a way to avoid require
      const module = require(modulePath);

      // Get the expected export name using the new conversion
      const exportName = this.toExportName(filename, type);
      const data = module[exportName] || module.default;

      if (!data) {
        throw new Error(ERROR_MESSAGES.NO_EXPORT_FOUND(filename, Object.keys(module).join(", ")));
      }

      return data;
    } catch (error) {
      throw new Error(
        ERROR_MESSAGES.FAILED_TO_LOAD_TYPESCRIPT_INSTANCE(
          filename,
          error instanceof Error ? error.message : String(error),
        ),
      );
    }
  }

  /**
   * Gets all available test instances of a specific type.
   * @param type - Type of test instances to retrieve ("setup" or "interaction")
   * @returns Array of test instances with filename and data
   */
  getAllTestInstances(type: "setup" | "interaction"): TestInstance[] {
    const instancesDir = path.join(__dirname, `../instances/${type}`);
    if (!fs.existsSync(instancesDir)) return [];

    const files = fs.readdirSync(instancesDir);

    // Only look for TypeScript files
    return files
      .filter((file) => file.endsWith(".ts"))
      .map((file) => ({
        filename: file,
        data: this.loadTestInstance(type, file),
      }));
  }
}
