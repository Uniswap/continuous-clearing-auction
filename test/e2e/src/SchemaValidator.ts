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

      // Try different export patterns - convert filename to camelCase and PascalCase
      const camelCaseFilename =
        filename.charAt(0).toLowerCase() + filename.slice(1).replace(/-([a-z])/g, (g) => g[1].toUpperCase());
      const pascalCaseFilename =
        filename.charAt(0).toUpperCase() + filename.slice(1).replace(/-([a-z])/g, (g) => g[1].toUpperCase());
      const data =
        module[filename] ||
        module[camelCaseFilename] ||
        module[pascalCaseFilename] ||
        module.default ||
        module[`${filename}Setup`] ||
        module[`${filename}Data`] ||
        module[`${filename}Interaction`];

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
