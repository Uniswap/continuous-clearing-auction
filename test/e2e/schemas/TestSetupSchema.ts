// TypeScript interfaces for test setup schema
import { ChainId } from "@uniswap/sdk-core";

export type Address = `0x${string}` & { readonly length: 42 };

export interface ForkConfig {
  rpcUrl: string;
  blockNumber: string;
}

export interface BalanceItem {
  address: Address; // Address of the account to set the balance for
  token: Address | string;
  amount: string;
}

export interface StepData {
  mpsPerBlock: number; // Milli-per-second (actually per-block) rate for this step
  blockDelta: number; // Number of blocks this step lasts
}

export interface GroupConfig {
  labelPrefix: string;
  count: number;
  startAmountEach?: string;
  startNativeEach?: string;
  addresses?: Address[];
}

export interface Environment {
  chainId?: ChainId | 31337; // 31337 is local Hardhat network
  startBlock: string;
  offsetBlocks?: number;
  blockTimeSec?: number;
  blockGasLimit?: string;
  txGasLimit?: string;
  baseFeePerGasWei?: string;
  fork?: ForkConfig;
  balances?: BalanceItem[];
  groups?: GroupConfig[];
}

export interface AuctionParameters {
  currency: Address | string;
  auctionedToken: Address | string;
  tokensRecipient: Address;
  fundsRecipient: Address;
  auctionDurationBlocks: number;
  claimDelayBlocks: number;
  tickSpacing: bigint | string;
  validationHook: Address;
  floorPrice: bigint | string;
  requiredCurrencyRaised: bigint | string;
  auctionStepsData?: string | StepData[]; // Optional: raw hex string or array of steps
}

export interface AdditionalToken {
  name: string;
  decimals: string;
  totalSupply: string;
  percentAuctioned: string;
}

export interface TestSetupData {
  name: string;
  env: Environment;
  auctionParameters: AuctionParameters;
  additionalTokens: AdditionalToken[];
}

// Type guards for runtime validation
export function isValidChainId(chainId: number): chainId is ChainId | 31337 {
  return Object.values(ChainId).includes(chainId as ChainId) || chainId === 31337;
}

export function isValidAddress(address: string): boolean {
  return /^0x[a-fA-F0-9]{40}$/.test(address);
}

export function isValidUint64(value: string): boolean {
  const num = BigInt(value);
  return num >= 0n && num <= 0xffffffffffffffffn;
}

export function isValidUint256(value: string): boolean {
  const num = BigInt(value);
  return num >= 0n && num <= 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffn;
}
