import * as fs from 'fs';
import * as path from 'path';
import Ajv from 'ajv';
import addFormats from 'ajv-formats';
import { TestSetupData } from '../schemas/TestSetupSchema';
import { TokenInteractionData } from '../schemas/TokenInteractionSchema';

// Re-export the TypeScript types for backward compatibility
export type SetupData = TestSetupData;
export type InteractionData = TokenInteractionData;

export interface TestInstance {
  filename: string;
  data: SetupData | InteractionData;
}

export class SchemaValidator {
  private ajv: Ajv;
  private schemas: Record<string, any> = {};

  constructor() {
    this.ajv = new Ajv({ 
      allErrors: true,
      strict: false  // Allow draft-2020-12 schemas
    });
    addFormats(this.ajv);
    this.loadSchemas();
  }

  private loadSchemas(): void {
    const schemaDir = path.join(__dirname, '../schemas');
    
    const schemaFiles = fs.readdirSync(schemaDir);
    schemaFiles.forEach(file => {
      if (file.endsWith('.json')) {
        const schemaName = file.replace('.json', '');
        const schemaPath = path.join(schemaDir, file);
        this.schemas[schemaName] = JSON.parse(fs.readFileSync(schemaPath, 'utf8'));
      }
    });
  }

  validateSetup(setupData: SetupData): boolean {
    const validate = this.ajv.compile(this.schemas.testSetupSchema);
    const valid = validate(setupData);
    if (!valid) {
      throw new Error(`Setup validation failed: ${JSON.stringify(validate.errors, null, 2)}`);
    }
    return true;
  }

  validateInteraction(interactionData: InteractionData): boolean {
    const validate = this.ajv.compile(this.schemas.tokenInteractionSchema);
    const valid = validate(interactionData);
    if (!valid) {
      throw new Error(`Interaction validation failed: ${JSON.stringify(validate.errors, null, 2)}`);
    }
    return true;
  }

  loadTestInstance(type: 'setup' | 'interaction', filename: string): SetupData | InteractionData {
    // Only load TypeScript files
    if (filename.endsWith('.ts')) {
      const baseName = filename.replace('.ts', '');
      return this.loadTypeScriptInstance(type, baseName);
    } else {
      // Try to find .ts version
      const tsFilePath = path.join(__dirname, `../instances/${type}/${filename}.ts`);
      
      if (fs.existsSync(tsFilePath)) {
        return this.loadTypeScriptInstance(type, filename);
      } else {
        throw new Error(`TypeScript test instance file not found: ${tsFilePath}`);
      }
    }
  }

  private loadTypeScriptInstance(type: 'setup' | 'interaction', filename: string): SetupData | InteractionData {
    try {
      if (type === 'setup') {
        // Use ts-node to load TypeScript files directly
        const modulePath = path.join(__dirname, `../instances/setup/${filename}.ts`);
        delete require.cache[modulePath];
        
        // Register ts-node
        require('ts-node').register();
        
        const module = require(modulePath);
        
        // Try different export patterns - convert filename to camelCase
        const camelCaseFilename = filename.replace(/-([a-z])/g, (g) => g[1].toUpperCase());
        const data = module[filename] || module[camelCaseFilename] || module.default || module[`${filename}Setup`] || module[`${filename}Data`];
        
        if (!data) {
          throw new Error(`No export found in ${filename}.ts. Available exports: ${Object.keys(module).join(', ')}`);
        }
        
        return data;
      } else {
        // Use ts-node to load TypeScript files directly
        const modulePath = path.join(__dirname, `../instances/interaction/${filename}.ts`);
        delete require.cache[modulePath];
        
        // Register ts-node
        require('ts-node').register();
        
        const module = require(modulePath);
        
        // Try different export patterns - convert filename to camelCase
        const camelCaseFilename = filename.replace(/-([a-z])/g, (g) => g[1].toUpperCase());
        const data = module[filename] || module[camelCaseFilename] || module.default || module[`${filename}Interaction`] || module[`${filename}Data`];
        
        if (!data) {
          throw new Error(`No export found in ${filename}.ts. Available exports: ${Object.keys(module).join(', ')}`);
        }
        
        return data;
      }
    } catch (error) {
      throw new Error(`Failed to load TypeScript instance ${filename}: ${error instanceof Error ? error.message : String(error)}`);
    }
  }

  private loadJsonInstance(type: 'setup' | 'interaction', filename: string): SetupData | InteractionData {
    const filePath = path.join(__dirname, `../instances/${type}/${filename}`);
    
    if (!fs.existsSync(filePath)) {
      throw new Error(`Test instance file not found: ${filePath}`);
    }
    
    const data = JSON.parse(fs.readFileSync(filePath, 'utf8'));
    
    // Validate the data
    if (type === 'setup') {
      this.validateSetup(data as SetupData);
    } else {
      this.validateInteraction(data as InteractionData);
    }
    
    return data;
  }

  getAllTestInstances(type: 'setup' | 'interaction'): TestInstance[] {
    const instancesDir = path.join(__dirname, `../instances/${type}`);
    if (!fs.existsSync(instancesDir)) return [];
    
    const files = fs.readdirSync(instancesDir);
    
    // Only look for TypeScript files
    return files
      .filter(file => file.endsWith('.ts'))
      .map(file => ({
        filename: file,
        data: this.loadTestInstance(type, file)
      }));
  }
}
