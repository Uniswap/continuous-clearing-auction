/**
 * Configuration constants for E2E tests
 * Centralizes hardcoded values for better maintainability
 */
import { Address } from '../schemas/TestSetupSchema';

// Network and blockchain constants
export const NATIVE_CURRENCY_ADDRESS = '0x0000000000000000000000000000000000000000' as Address;
export const ZERO_ADDRESS = '0x0000000000000000000000000000000000000000' as Address;

// Hardhat network methods
export const HARDHAT_METHODS = {
  MINE: 'hardhat_mine',
  IMPERSONATE_ACCOUNT: 'hardhat_impersonateAccount',
  STOP_IMPERSONATING_ACCOUNT: 'hardhat_stopImpersonatingAccount',
  SET_BALANCE: 'hardhat_setBalance',
} as const;

// True constants - values that never change
export const MPS = 10000000; // 1e7 - Million Price Steps
export const MAX_SYMBOL_LENGTH = 4;
export const HEX_PADDING_LENGTH = 16;
export const DEFAULT_TOTAL_SUPPLY = '1000000000000000000000'; // 1000 tokens with 18 decimals
// Error messages
export const ERROR_MESSAGES = {
  TOKEN_NOT_FOUND: (tokenName: string) => `Token ${tokenName} not found`,
  AUCTIONED_TOKEN_NOT_FOUND: (tokenName: string) => `Auctioned token ${tokenName} not found`,
  AUCTION_PARAMETERS_NOT_FOUND: 'AuctionParameters struct not found in auction artifact',
  BALANCE_ASSERTION_FAILED: (address: string, token: string, expected: string, actual: string) => 
    `Balance assertion failed for ${address} token ${token}. Expected ${expected}, got ${actual}`,
  EXPECTED_REVERT_NOT_FOUND: (expected: string, actual: string) => 
    `Expected revert data to contain "${expected}", but got: ${actual}`,
  UNSUPPORTED_AMOUNT_TYPE: (type: string) => `Unknown amount type: ${type}`,
  UNSUPPORTED_PRICE_TYPE: (type: string) => `Unknown price type: ${type}`,
} as const;

// Logging prefixes
export const LOG_PREFIXES = {
  DEPLOY: '   🪙',
  SUCCESS: '   ✅',
  ERROR: '   ❌',
  WARNING: '   ⚠️',
  INFO: '   🔍',
  BID: '   🔸',
  ASSERTION: '   💰',
  CONFIG: '   📊',
  AUCTION: '   🏛️',
  PHASE: '🎯',
  TEST: '🧪',
  FINAL: '🎉',
} as const;
