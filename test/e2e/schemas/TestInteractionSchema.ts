// TypeScript interfaces for token interaction schema

export type Address = `0x${string}` & { readonly length: 42 };

export enum AssertionInterfaceType {
  BALANCE = 'balance',
  TOTAL_SUPPLY = 'totalSupply',
  EVENT = 'event',
  POOL = 'pool',
}

export enum ActionType {
  ADMIN_ACTION = 'AdminAction',
  TRANSFER_ACTION = 'TransferAction',
}

export enum Side {
  INPUT = 'input',
  OUTPUT = 'output',
}

export enum AmountType {
  RAW = 'raw',
  PERCENT_OF_SUPPLY = 'percentOfSupply',
  BASIS_POINTS = 'basisPoints',
  PERCENT_OF_GROUP = 'percentOfGroup',
}

export enum PriceType {
  RAW = 'raw',
  TICK = 'tick',
}

export enum AdminActionMethod {
  SWEEP_CURRENCY = 'sweepCurrency',
  SWEEP_UNSOLD_TOKENS = 'sweepUnsoldTokens',
}

export interface AmountConfig {
  side: Side;
  type: AmountType;
  value: string;
  variation?: string;
  token?: Address | string;
}

export interface PriceConfig {
  type: PriceType;
  value: string;
  variation?: string;
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
  address: Address;
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
  method: AdminActionMethod;
}

export interface TransferAction {
  atBlock: number;
  value: {
    from: Address;
    to: Address | string;
    token: Address | string;
    amount: string;
  };
}

export interface BalanceAssertion {
  type: AssertionInterfaceType.BALANCE;
  address: Address;
  token: Address | string;
  expected: string;
}

export interface TotalSupplyAssertion {
  type: AssertionInterfaceType.TOTAL_SUPPLY;
  token: Address | string;
  expected: string;
}

export interface EventAssertion {
  type: AssertionInterfaceType.EVENT;
  eventName: string;
  expectedArgs: Record<string, any>;
}

export interface PoolAssertion {
  type: AssertionInterfaceType.POOL;
  tick?: string;
  sqrtPriceX96?: string;
  liquidity?: string;
}


export type Assertion = BalanceAssertion | TotalSupplyAssertion | EventAssertion | PoolAssertion;

export interface AssertionInfo {
  atBlock: number;
  reason: string;
  assert: Assertion;
}

export interface TestInteractionData {
  namedBidders?: NamedBidder[];
  groups?: Group[];
  actions?: Array<{
    type: ActionType;
    interactions: Array<AdminAction[] | TransferAction[]>;
  }>;
  assertions?: AssertionInfo[];
}

// Type guards for runtime validation

export function isValidAmountType(type: string): type is AmountConfig['type'] {
  return Object.values(AmountType).includes(type as AmountType);
}

export function isValidPriceType(type: string): type is PriceConfig['type'] {
  return Object.values(PriceType).includes(type as PriceType);
}

export function isValidAmountSide(side: string): side is AmountConfig['side'] {
  return side === Side.INPUT || side === Side.OUTPUT;
}

export function isValidAdminActionKind(kind: string): kind is AdminAction['method'] {
  return Object.values(AdminActionMethod).includes(kind as AdminActionMethod);
}
