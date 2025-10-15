import { Contract, ContractTransaction, TransactionLike } from "ethers";
import { Address } from "../schemas/TestSetupSchema";

// Import contract artifacts to get proper typing
import auctionArtifact from "../../../out/Auction.sol/Auction.json";
import auctionFactoryArtifact from "../../../out/AuctionFactory.sol/AuctionFactory.json";
import mockTokenArtifact from "../../../out/WorkingCustomMockToken.sol/WorkingCustomMockToken.json";
import { ActionType, AdminAction, AssertionInfo, TransferAction } from "../schemas/TestInteractionSchema";
import { InternalBidData } from "./BidSimulator";

// Contract types with proper ABI-based typing
export type AuctionContract = Contract & {
  interface: typeof auctionArtifact.abi;
};
export type AuctionFactoryContract = Contract & {
  interface: typeof auctionFactoryArtifact.abi;
};
export type TokenContract = Contract & {
  interface: typeof mockTokenArtifact.abi;
};

// Event data types
export interface BidEventData {
  bidData: {
    atBlock: number;
    amount: {
      side: "input" | "output";
      type: "raw" | "percentOfSupply" | "basisPoints" | "percentOfGroup";
      value: string;
      variation?: string;
      token?: Address | string;
    };
    price: {
      type: "raw" | "tick";
      value: string;
      variation?: string;
    };
    previousTick: number;
    hookData?: string;
    expectRevert?: string;
  };
  bidder: string;
  type: "named" | "group";
  group?: string;
}

export interface ActionEventData {
  actionType: "AdminAction" | "TransferAction";
  atBlock: number;
  method?: string;
  value?: {
    from: Address;
    to: Address | string;
    token: Address | string;
    amount: string;
  };
}

export interface AssertionEventData {
  atBlock: number;
  reason: string;
  assert: {
    type: "balance" | "totalSupply" | "event" | "pool";
    address?: Address;
    token?: Address | string;
    expected?: string;
    eventName?: string;
    expectedArgs?: Record<string, any>;
    tick?: string;
    sqrtPriceX96?: string;
    liquidity?: string;
  };
}

// Test result types
export interface TestExecutionResult {
  success: boolean;
  error?: string;
  duration?: number;
}

export interface TestCombinationResult {
  setupFile: string;
  interactionFile: string;
  result: TestExecutionResult;
}

// Configuration types
export interface AuctionConfig {
  currency: Address;
  tokensRecipient: Address;
  fundsRecipient: Address;
  startBlock: number;
  endBlock: number;
  claimBlock: number;
  tickSpacing: number;
  validationHook: Address;
  floorPrice: string;
  auctionStepsData: string;
}

export interface TransactionInfo {
  tx: ContractTransaction | TransactionLike<string>;
  from: string | null;
  msg?: string;
  expectRevert?: string;
}

export interface HashWithRevert {
  hash: string;
  expectRevert?: string;
}

export enum EventType {
  BID = "bid",
  ACTION = "action",
  ASSERTION = "assertion",
}

export type ActionData = { actionType: ActionType } & (AdminAction | TransferAction);

// Union type for all possible event data types
export type EventInternalData = InternalBidData | ActionData | AssertionInfo;

export interface EventData {
  type: EventType;
  atBlock: number;
  data: EventInternalData;
}
