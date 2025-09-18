import * as fs from 'fs';
import * as path from 'path';
import Ajv, { JSONSchemaType, ValidateFunction } from 'ajv';
import addFormats from 'ajv-formats';

// Type definitions for our schemas
export interface SetupData {
  env: {
    chainId: number;
    startBlock: string;
    blockTimeSec?: number;
    blockGasLimit?: string;
    txGasLimit?: string;
    baseFeePerGasWei?: string;
    fork?: {
      rpcUrl: string;
      blockNumber: string;
    };
    balances?: Array<{
      address: string;
      token: string;
      amount: string;
    }>;
  };
  auctionParameters: {
    currency: string;
    auctionedToken: string;
    tokensRecipient: string;
    fundsRecipient: string;
    startOffsetBlocks: number;
    auctionDurationBlocks: number;
    claimDelayBlocks: number;
    graduationThresholdMps: string;
    tickSpacing: number;
    validationHook: string;
    floorPrice: string;
  };
  additionalTokens: Array<{
    name: string;
    decimals: string;
    totalSupply: string;
    percentAuctioned: string;
  }>;
}

export interface InteractionData {
  timeBase: 'auctionStart' | 'genesisBlock';
  namedBidders?: Array<{
    address: string;
    label?: string;
    bids: Array<{
      atBlock: number;
      amount: {
        side: 'input' | 'output';
        type: 'raw' | 'percentOfSupply' | 'basisPoints' | 'percentOfGroup';
        value: string | number;
        variation?: string | number;
        token?: string;
      };
      price: {
        type: 'raw' | 'tick';
        value: string | number;
        variation?: string | number;
      };
      hookData?: string;
      expectRevert?: string;
    }>;
    recurringBids?: Array<any>;
  }>;
  groups?: Array<any>;
  actions?: Array<any>;
  checkpoints?: Array<{
    atBlock: number;
    reason: string;
    assert: {
      type: 'balance';
      address: string;
      token: string;
      expected: string;
    };
  }>;
}

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
    const filePath = path.join(__dirname, `../instances/${type}/${filename}`);
    return JSON.parse(fs.readFileSync(filePath, 'utf8'));
  }

  getAllTestInstances(type: 'setup' | 'interaction'): TestInstance[] {
    const instancesDir = path.join(__dirname, `../instances/${type}`);
    if (!fs.existsSync(instancesDir)) return [];
    
    return fs.readdirSync(instancesDir)
      .filter(file => file.endsWith('.json'))
      .map(file => ({
        filename: file,
        data: this.loadTestInstance(type, file)
      }));
  }
}
