// TypeScript interfaces for test interaction schema
export type Address = `0x${string}` & { readonly length: 42 };

export enum AssertionInterfaceType {
  BALANCE = 'balance',
  TOTAL_SUPPLY = 'totalSupply',
  EVENT = 'event',
  AUCTION = 'auction',
  REVERT = 'revert',
}

export enum ActionType {
  ADMIN_ACTION = 'AdminAction',
  TRANSFER_ACTION = 'TransferAction',
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
  previousTick: number;
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
  previousTick?: number;
  previousTickIncrement?: number;
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
  startBlock: number;
  amount: AmountConfig;
  price: PriceConfig;
  previousTick: number;
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
    expectRevert?: string;
  };
}

export interface BalanceAssertion {
  type: AssertionInterfaceType.BALANCE;
  address: Address;
  token: Address | string;
  expected: string;
  variance?: string; // Optional variance field. Can be a ratio (e.g., "0.05") or percentage (e.g., "5%")
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

export interface RevertAssertion {
  type: AssertionInterfaceType.REVERT;
  expected: string;
}

export interface AuctionAssertion {
  type: AssertionInterfaceType.AUCTION;
  isGraduated: boolean;
  clearingPrice: string | VariableAmount;
  currencyRaised: string | VariableAmount;
  latestCheckpoint: InternalCheckpointStruct;
}

export interface InternalCheckpointStruct {
  clearingPrice: string | VariableAmount;
  totalClearedX7X7: string | VariableAmount;
  cumulativeSupplySoldToClearingPriceX7X7: string | VariableAmount;
  cumulativeMpsPerPrice: string | VariableAmount;
  cumulativeMps: string | VariableAmount;
  prev: string | VariableAmount;
  next: string | VariableAmount;
}

export interface VariableAmount {
  amount: string;
  variation: string;
}

export type Assertion = BalanceAssertion | TotalSupplyAssertion | EventAssertion | AuctionAssertion;

export interface AssertionInfo {
  atBlock: number;
  reason: string;
  assert: Assertion;
}

export interface TestInteractionData {
  name: string;
  namedBidders?: NamedBidder[];
  groups?: Group[];
  actions?: Array<{
    type: ActionType;
    interactions: Array<AdminAction[] | TransferAction[]>;
  }>;
  assertions?: AssertionInfo[];
}

// Type guards for runtime validation

export function isValidPriceType(type: string): type is PriceConfig['type'] {
  return Object.values(PriceType).includes(type as PriceType);
}

export function isValidAdminActionKind(kind: string): kind is AdminAction['method'] {
  return Object.values(AdminActionMethod).includes(kind as AdminActionMethod);
}
