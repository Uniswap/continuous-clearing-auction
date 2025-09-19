// TypeScript interfaces for test setup schema

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

export interface Environment {
  chainId?: 1 | 5 | 11155111 | 42161 | 8453 | 31337;
  startBlock: string;
  blockTimeSec?: number;
  blockGasLimit?: string;
  txGasLimit?: string;
  baseFeePerGasWei?: string;
  fork?: ForkConfig;
  balances?: BalanceItem[];
}

export interface AuctionParameters {
  currency: Address | string;
  auctionedToken: Address | string;
  tokensRecipient: Address;
  fundsRecipient: Address;
  startOffsetBlocks: number;
  auctionDurationBlocks: number;
  claimDelayBlocks: number;
  graduationThresholdMps: string;
  tickSpacing: number;
  validationHook: Address;
  floorPrice: string;
}

export interface AdditionalToken {
  name: string;
  decimals: string;
  totalSupply: string;
  percentAuctioned: string;
}

export interface TestSetupData {
  env: Environment;
  auctionParameters: AuctionParameters;
  additionalTokens: AdditionalToken[];
}

// Type guards for runtime validation
export function isValidChainId(chainId: number): chainId is 1 | 5 | 11155111 | 42161 | 8453 | 31337 {
  return [1, 5, 11155111, 42161, 8453, 31337].includes(chainId);
}

export function isValidAddress(address: string): boolean {
  return /^0x[a-fA-F0-9]{40}$/.test(address);
}

export function isValidUint64(value: string): boolean {
  const num = BigInt(value);
  return num >= 0n && num <= 0xFFFFFFFFFFFFFFFFn;
}

export function isValidUint256(value: string): boolean {
  const num = BigInt(value);
  return num >= 0n && num <= 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFn;
}
