// TypeScript interfaces for token interaction schema
// This replaces the JSON schema with proper TypeScript types

export type TimeBase = 'auctionStart' | 'genesisBlock';

export interface AmountConfig {
  side: 'input' | 'output';
  type: 'raw' | 'percentOfSupply' | 'basisPoints' | 'percentOfGroup';
  value: string | number;
  variation?: string | number;
  token?: string;
}

export interface PriceConfig {
  type: 'raw' | 'tick';
  value: string | number;
  variation?: string | number;
}

export interface BidData {
  atBlock: number;
  amount: AmountConfig;
  price: PriceConfig;
  hookData?: string;
  expectRevert?: string;
}

export interface RecurringBid {
  startBlock: number;
  intervalBlocks: number;
  occurrences: number;
  amount: AmountConfig;
  price: PriceConfig;
  amountFactor?: number;
  priceFactor?: number;
  hookData?: string;
}

export interface NamedBidder {
  address: string;
  label?: string;
  bids: BidData[];
  recurringBids: RecurringBid[];
}

export interface Group {
  labelPrefix: string;
  count: number;
  startOffsetBlocks: number;
  amount: AmountConfig;
  price: PriceConfig;
  rotationIntervalBlocks: number;
  betweenRoundsBlocks: number;
  rounds: number;
  hookData?: string;
}

export interface AdminAction {
  atBlock: number;
  value: {
    kind: 'sweepCurrency' | 'sweepUnsoldTokens';
  };
}

export interface TransferAction {
  atBlock: number;
  value: {
    from: string;
    to: string;
    token: string;
    amount: string;
  };
}

export interface BalanceAssertion {
  type: 'balance';
  address: string;
  token: string;
  expected: string;
}

export interface Checkpoint {
  atBlock: number;
  reason: string;
  assert: BalanceAssertion;
}

export interface TokenInteractionData {
  timeBase: TimeBase;
  namedBidders?: NamedBidder[];
  groups?: Group[];
  actions?: Array<{
    type: 'AdminAction' | 'TransferAction';
    interactions: Array<AdminAction[] | TransferAction[]>;
  }>;
  checkpoints?: Checkpoint[];
}

// Type guards for runtime validation
export function isValidTimeBase(timeBase: string): timeBase is TimeBase {
  return timeBase === 'auctionStart' || timeBase === 'genesisBlock';
}

export function isValidAmountType(type: string): type is AmountConfig['type'] {
  return ['raw', 'percentOfSupply', 'basisPoints', 'percentOfGroup'].includes(type);
}

export function isValidPriceType(type: string): type is PriceConfig['type'] {
  return ['raw', 'tick'].includes(type);
}

export function isValidAmountSide(side: string): side is AmountConfig['side'] {
  return side === 'input' || side === 'output';
}

export function isValidAdminActionKind(kind: string): kind is AdminAction['value']['kind'] {
  return ['sweepCurrency', 'sweepUnsoldTokens'].includes(kind);
}
