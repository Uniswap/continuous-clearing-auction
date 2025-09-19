/**
 * Enhanced type definitions for E2E tests
 * Improves type safety and reduces 'any' usage
 */

import { Contract } from 'ethers';
import { Address } from '../schemas/TestSetupSchema';

// Import contract artifacts to get proper typing
import auctionArtifact from '../../../out/Auction.sol/Auction.json';
import auctionFactoryArtifact from '../../../out/AuctionFactory.sol/AuctionFactory.json';
import mockTokenArtifact from '../../../out/WorkingCustomMockToken.sol/WorkingCustomMockToken.json';

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
      side: 'input' | 'output';
      type: 'raw' | 'percentOfSupply' | 'basisPoints' | 'percentOfGroup';
      value: string;
      variation?: string;
      token?: Address | string;
    };
    price: {
      type: 'raw' | 'tick';
      value: string;
      variation?: string;
    };
    previousTick: number;
    hookData?: string;
    expectRevert?: string;
  };
  bidder: string;
  type: 'named' | 'group';
  group?: string;
}

export interface ActionEventData {
  actionType: 'AdminAction' | 'TransferAction';
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
    type: 'balance' | 'totalSupply' | 'event' | 'pool';
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


// Network types
export interface NetworkProvider {
  send(method: string, params: unknown[]): Promise<unknown>;
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
  graduationThresholdMps: number;
  tickSpacing: number;
  validationHook: Address;
  floorPrice: string;
  auctionStepsData: string;
}

export interface TokenConfig {
  name: string;
  decimals: string;
  totalSupply: string;
  percentAuctioned: string;
}

// Error types
export class E2ETestError extends Error {
  constructor(
    message: string,
    public readonly context?: Record<string, any>
  ) {
    super(message);
    this.name = 'E2ETestError';
  }
}

export class AuctionDeploymentError extends E2ETestError {
  constructor(message: string, context?: Record<string, any>) {
    super(message, context);
    this.name = 'AuctionDeploymentError';
  }
}

export class BidExecutionError extends E2ETestError {
  constructor(message: string, context?: Record<string, any>) {
    super(message, context);
    this.name = 'BidExecutionError';
  }
}

export class AssertionError extends E2ETestError {
  constructor(message: string, context?: Record<string, any>) {
    super(message, context);
    this.name = 'AssertionError';
  }
}
