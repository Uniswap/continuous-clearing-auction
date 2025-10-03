/**
 * Configuration constants for E2E tests
 * Centralizes hardcoded values for better maintainability
 */
import { Address } from "../schemas/TestSetupSchema";

// Network and blockchain constants
export const NATIVE_CURRENCY_ADDRESS = "0x0000000000000000000000000000000000000000" as Address;
export const ZERO_ADDRESS = "0x0000000000000000000000000000000000000000" as Address;
export const PERMIT2_ADDRESS = "0x000000000022D473030F116dDEE9F6B43aC78BA3" as Address;
export const UINT_160_MAX = "0xffffffffffffffffffffffffffffffffffffffff";
export const UINT_48_MAX = "0xffffffffffff";

// ERC20 constants
export const MAX_UINT256 = "0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff";

// Hardhat network methods
export const HARDHAT_METHODS = {
  MINE: "hardhat_mine",
  IMPERSONATE_ACCOUNT: "hardhat_impersonateAccount",
  STOP_IMPERSONATING_ACCOUNT: "hardhat_stopImpersonatingAccount",
  SET_BALANCE: "hardhat_setBalance",
} as const;

// True constants - values that never change
export const MPS = 10000000; // 1e7 - Million Price Steps
export const MAX_SYMBOL_LENGTH = 4;
export const HEX_PADDING_LENGTH = 16;
export const DEFAULT_TOTAL_SUPPLY = "1000000000000000000000"; // 1000 tokens with 18 decimals
// Error messages
export const ERROR_MESSAGES = {
  // AuctionDeployer errors
  AUCTIONED_TOKEN_NOT_FOUND: (tokenName: string) => `Auctioned token ${tokenName} not found`,
  AUCTION_PARAMETERS_NOT_FOUND: "AuctionParameters struct not found in auction artifact",
  AUCTION_FACTORY_NOT_DEPLOYED: "AuctionFactory not deployed. Call initialize() first.",
  AUCTION_DEPLOYER_NOT_INITIALIZED: "AuctionDeployer not initialized. Call initialize() first.",
  AUCTION_CREATION_FAILED: (errorMessage: string) => `Auction creation failed. Original error: ${errorMessage}`,
  TOKEN_NOT_FOUND: (tokenName: string) => `Token ${tokenName} not found`,
  AUCTION_NOT_DEPLOYED: "Auction not deployed. Call createAuction() first.",

  // AssertionEngine errors
  TOKEN_IDENTIFIER_NOT_FOUND: (tokenIdentifier: string) => `Token with identifier ${tokenIdentifier} not found.`,
  CANNOT_VALIDATE_EQUALITY: "Can only validate equality for non-object types",
  TOKEN_NOT_FOUND_BY_ADDRESS: (tokenAddress: string) => `Token not found for address: ${tokenAddress}`,
  TOTAL_SUPPLY_ASSERTION_FAILED: (expected: string, actual: string) =>
    `Total supply assertion failed: expected ${expected}, got ${actual}`,
  AUCTION_ASSERTION_FAILED: (expected: any, actual: any, field?: string, variance?: string) =>
    variance
      ? `Auction assertion failed${field ? ` for ${field}` : ""}. Expected ${expected} ± ${variance}, got ${actual}`
      : `Auction assertion failed${field ? ` for ${field}` : ""}. Expected ${expected}, got ${actual}`,
  AUCTION_CHECKPOINT_ASSERTION_FAILED: (expected: any, actual: any, field?: string, variance?: string) =>
    variance
      ? `Auction latestCheckpoint assertion failed${
          field ? ` for ${field}` : ""
        }. Expected ${expected} ± ${variance}, got ${actual}`
      : `Auction latestCheckpoint assertion failed${field ? ` for ${field}` : ""}. Expected ${expected}, got ${actual}`,
  BLOCK_NOT_FOUND: (currentBlock: number) => `Block ${currentBlock} not found`,
  EVENT_ASSERTION_FAILED: (eventName: string) =>
    `Event assertion failed: Event '${eventName}' not found with expected arguments`,
  BALANCE_ASSERTION_FAILED: (address: string, token: string, expected: string, actual: string, variance?: string) =>
    variance
      ? `Balance assertion failed for ${address} token ${token}. Expected ${expected} ± ${variance}, got ${actual}`
      : `Balance assertion failed for ${address} token ${token}. Expected ${expected}, got ${actual}`,

  // BidSimulator errors
  PERCENT_OF_SUPPLY_INVALID_SIDE:
    "PERCENT_OF_SUPPLY can only be used for auctioned token (OUTPUT), not currency (INPUT)",
  EXPECTED_REVERT_NOT_FOUND: (expected: string, actual: string) =>
    `Expected revert data to contain "${expected}", but got: ${actual}`,

  // E2ECliRunner errors
  NO_INSTANCE_FOUND: (filePath: string) => `No instance found in ${filePath}`,
  FAILED_TO_LOAD_FILE: (filePath: string, error: string) => `Failed to load ${filePath}: ${error}`,

  // SingleTestRunner errors
  BLOCK_ALREADY_PAST_START: (currentBlock: number, auctionStartBlock: number) =>
    `Current block ${currentBlock} is already past auction start block ${auctionStartBlock}`,
  BLOCK_ALREADY_MINED: (blockNum: number) => `Block ${blockNum} is already mined`,
  EXPECTED_REVERT_MISMATCH: (expected: string, actual: string) => `Expected revert "${expected}" but got: ${actual}`,

  // SchemaValidator errors
  TYPESCRIPT_FILE_NOT_FOUND: (tsFilePath: string) => `TypeScript test instance file not found: ${tsFilePath}`,
  NO_EXPORT_FOUND: (filename: string, availableExports: string) =>
    `No export found in ${filename}.ts. Available exports: ${availableExports}`,
  FAILED_TO_LOAD_TYPESCRIPT_INSTANCE: (filename: string, error: string) =>
    `Failed to load TypeScript instance ${filename}: ${error}`,
} as const;

// Logging prefixes
export const LOG_PREFIXES = {
  RUN: "   🚀",
  DEPLOY: "   🪙",
  SUCCESS: "   ✅",
  ERROR: "   ❌",
  WARNING: "   ⚠️",
  INFO: "   🔍",
  DEBUG: "   🐛",
  BID: "   🔸",
  ASSERTION: "   💰",
  CONFIG: "   📊",
  AUCTION: "   🏛️",
  PHASE: "🎯",
  TEST: "🧪",
  FINAL: "🎉",
  NOTE: "💡",
  FILES: "📁",
} as const;

export enum TYPES {
  OBJECT = "object",
  ERROR = "error",
}

export const METHODS = {
  HARDHAT: {
    IMPERSONATE_ACCOUNT: "hardhat_impersonateAccount",
    STOP_IMPERSONATING_ACCOUNT: "hardhat_stopImpersonatingAccount",
    SET_BALANCE: "hardhat_setBalance",
    MINE: "hardhat_mine",
    RESET: "hardhat_reset",
    SET_CODE: "hardhat_setCode",
  },
  DEBUG: {
    TRACE_TRANSACTION: "debug_traceTransaction",
  },
  EVM: {
    SET_AUTOMINE: "evm_setAutomine",
    SET_INTERVAL_MINING: "evm_setIntervalMining",
    MINE: "evm_mine",
  },
};

export const TYPE_FIELD = "type";
export const PENDING_STATE = "pending";
export const SETUP = "setup";
export const INTERACTION = "interaction";
