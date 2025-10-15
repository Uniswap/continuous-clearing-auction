# TWAP Auction E2E Test Suite

This directory contains the end-to-end (E2E) test suite for the TWAP Auction system. The test suite allows one to define complex auction scenarios using TypeScript interfaces and validate the entire auction lifecycle from deployment to completion.

## ⚠️ Important Notes

- **Auction Start Block**: Cannot be block 1. Must be block 2 or later.
- **Interaction Timing**: Interactions can begin on the same block as the auction start block, but not before

## ❓ Frequently Asked Questions

### How can I check events?

You can check events by defining an assertion with the `EVENT` type:

```typescript
{
  atBlock: 50,
  reason: "Check event emission",
  assert: {
    type: AssertionInterfaceType.EVENT,
    eventName: "BidSubmitted",
    expectedArgs: {
      bidder: "0x1111111111111111111111111111111111111111",
      amount: "90000000000000000000000000000000"
    }
  }
}
```

**How it works:**
- Events emitted on-chain are reconstructed from the contract ABI
- Each event is formatted as `"EventName(arg1,arg2,arg3)"`
- The test checks if the event name and arguments match your assertion
- `expectedArgs` is optional - keys are for logging clarity only
- You can use the exact event format: `"EventName(arg1,arg2,arg3)"` as the `eventName`

### How can I check for expected reverts?

For any action you wish to check a revert on, add the `expectRevert` field:

```typescript
{
  type: ActionType.TRANSFER_ACTION,
  interactions: [
    [
      {
        atBlock: 200,
        value: {
          from: "0x4444444444444444444444444444444444444444" as Address,
          to: "0x2222222222222222222222222222222222222222" as Address,
          token: "USDC",
          amount: "1000000", // 1 USDC
          expectRevert: "ERC20InsufficientBalance"
        }
      }
    ]
  ]
}
```

**How it works:**
- On-chain reverts are decoded using the contract ABI
- Reverts are formatted as `"ExampleRevert(arg1,arg2,arg3)"`
- The test checks if the revert contains your `expectRevert` string
- You can use just the revert name or include arguments

### How can I add variance to checkpoint fields?

You can add variance to any checkpoint field to accommodate bid variance by using the `VariableAmount` structure:

```typescript
{
  atBlock: 50,
  reason: "Check auction state with variance",
  assert: {
    type: AssertionInterfaceType.AUCTION,
    currencyRaised: {
      amount: "1000000000000000000000", // Expected amount
      variation: "5%" // 5% variance allowed
    },
    clearingPrice: {
      amount: "79228162514264337593543950336000", // Expected price
      variation: "0.1" // 10% variance allowed (decimal format)
    }
  }
}
```

**How it works:**
- Use `amount` for the expected value
- Use `variation` for the allowed variance (supports both percentage "5%" and decimal "0.05" formats)
- The test checks if the actual value is within the variance bounds
- Useful for accommodating bid variance and MEV scenarios
- Works with all auction state fields: `currencyRaised`, `clearingPrice`, `isGraduated`
- Also works with checkpoint fields like `totalCleared`, `totalBids`, etc.

## ✨ Key Features

- **🎯 Targeted Testing** - Run only compatible setup/interaction combinations
- **⚡ Same-Block Execution** - Multiple transactions in the same block with query priority
- **📊 Comprehensive Logging** - Detailed execution traces and state information
- **🛠️ Flexible Interface** - npm scripts, command-line options, and shell scripts
- **🔍 Real Contract Integration** - Uses actual Foundry auction contracts, not mocks
- **📋 Type Safety** - TypeScript interfaces for compile-time validation and IDE support
- **🎮 MEV Testing** - Test transaction ordering and arbitrage scenarios

## 🏗️ Architecture

The E2E test suite is built on top of Hardhat and consists of several key components:

### Core Components

- **`src/SchemaValidator.ts`** - Loads and validates TypeScript instance files
- **`src/AuctionDeployer.ts`** - Deploys auction contracts and sets up the environment
- **`src/BidSimulator.ts`** - Simulates bids and interactions with the auction
- **`src/AssertionEngine.ts`** - Validates checkpoints and assertions
- **`src/SingleTestRunner.ts`** - Orchestrates the complete test execution
- **`src/MultiTestRunner.ts`** - Manages multiple test combinations
- **`src/E2ECliRunner.ts`** - Command-line interface for running specific combinations
- **`src/constants.ts`** - Centralized configuration and error messages

### Test Data

- **`instances/setup/`** - TypeScript files defining auction setup parameters
- **`instances/interaction/`** - TypeScript files defining bid scenarios and interactions
- **`schemas/`** - TypeScript interface definitions for type safety

## 🔄 Execution Flow

The test suite follows a structured execution flow:

1. **📋 Type Validation** - Validate setup and interaction TypeScript files
2. **🏗️ Environment Setup** - Deploy auction contracts and configure tokens
3. **⚖️ Balance Setup** - Set initial balances for test accounts
4. **📅 Event Scheduling** - Collect and sort all events (bids, actions, checkpoints) by block
5. **🔀 Block Grouping** - Group events by block number for same-block execution
6. **🎯 Execution** - Execute events block by block with query priority
7. **✅ Validation** - Validate checkpoints and assertions
8. **📊 Reporting** - Generate test results and final state

### Same-Block Execution Details

- **Block Mining**: Only mines once per block, then executes all events in that block
- **Query Priority**: Checkpoints/queries execute before transactions in the same block
- **Transaction Ordering**: Maintains original order for same-type events
- **State Preservation**: All state changes are preserved between transactions

## 🚀 Quick Start

### Prerequisites

- Node.js (v18+ recommended)
- npm or yarn
- Hardhat installed globally or locally

### Running Tests

```bash
# From the project root directory
npm run e2e

# Or run directly with Hardhat
npx hardhat test test/e2e/tests/e2e.test.ts

# Or use the shell script
./test/e2e/run-e2e-tests.sh
```

### Available Scripts

- `npm run e2e` - Run the main E2E test suite
- `npm run e2e:run` - Run predefined setup/interaction combinations
- `npm run e2e:shell` - Run using the shell script with compilation

### Command-Line Options

```bash
# Run predefined combinations
npm run e2e:run

# Run specific combination
npx ts-node test/e2e/src/E2ECliRunner.ts --setup SimpleSetup.ts --interaction SimpleInteraction.ts

# Show help
npx ts-node test/e2e/src/E2ECliRunner.ts --help

# Verbose output
./test/e2e/run-e2e-tests.sh --verbose
```

## 📋 Test Structure

The E2E test suite now uses **TypeScript interfaces** instead of JSON schemas for better type safety, IDE support, and maintainability.

### Benefits of TypeScript Schemas

- **Type Safety**: Compile-time validation of test data structure with strict `Address` type (42-char hex strings)
- **IDE Support**: Auto-completion, refactoring, and error detection
- **Maintainability**: Easier to update and extend test scenarios
- **Runtime Validation**: Built-in type guards for runtime checks
- **Documentation**: Self-documenting interfaces with clear type definitions
- **Address Validation**: Enforces proper Ethereum address format (0x + 40 hex digits)

### Address Type

The E2E test suite uses a strict `Address` type that ensures all addresses are properly formatted:

```typescript
export type Address = `0x${string}` & { readonly length: 42 };
```

This type:
- **Enforces 0x prefix**: Must start with `0x`
- **Enforces exact length**: Must be exactly 42 characters (0x + 40 hex digits)
- **Provides compile-time safety**: TypeScript will catch invalid addresses at compile time
- **Supports type assertions**: Use `as Address` for string literals

**Examples:**
```typescript
// ✅ Valid addresses
"0x1111111111111111111111111111111111111111" as Address
"0x0000000000000000000000000000000000000000" as Address

// ❌ Invalid addresses (TypeScript errors)
"0x111"  // Too short
"1111111111111111111111111111111111111111"  // Missing 0x
"0x11111111111111111111111111111111111111111"  // Too long
```

### Setup Schema

The setup schema defines the auction environment using TypeScript interfaces:

```typescript
import { TestSetupData, Address } from '../schemas/TestSetupSchema';

export const simpleSetup: TestSetupData = {
  env: {
    chainId: 31337,
    startBlock: "2",
    balances: [
      {
        address: "0x1111111111111111111111111111111111111111" as Address,
        token: "0x0000000000000000000000000000000000000000" as Address,
        amount: "1000000000000000000000"
      }
    ]
  },
  auctionParameters: {
    currency: "0x0000000000000000000000000000000000000000" as Address,
    auctionedToken: "SimpleToken",
    tokensRecipient: "0x2222222222222222222222222222222222222222" as Address,
    fundsRecipient: "0x3333333333333333333333333333333333333333" as Address,
    auctionDurationBlocks: 50,
    claimDelayBlocks: 10,
    tickSpacing: 100,
    validationHook: "0x0000000000000000000000000000000000000000" as Address,
    floorPrice: "79228162514264337593543950336000"
  },
  additionalTokens: [
    {
      name: "SimpleToken",
      decimals: "18",
      totalSupply: "1000000000000000000000000",
      percentAuctioned: "10"
    }
  ]
};
```

### Interaction Schema

The interaction schema defines bid scenarios and assertions using TypeScript interfaces:

```typescript
import { TestInteractionData, Address, AssertionInterfaceType } from '../schemas/TestInteractionSchema';

export const simpleInteraction: TestInteractionData = {
  namedBidders: [
    {
      address: "0x1111111111111111111111111111111111111111" as Address,
      label: "SimpleBidder",
      bids: [
        {
          atBlock: 10,
          amount: { side: "input", type: "raw", value: "1000000000000000000" },
          price: { type: "raw", value: "87150978765690771352898345369600" },
          expectRevert: "InsufficientBalance"
        }
      ],
      recurringBids: []
    }
  ],
  assertions: [
    {
      atBlock: 20,
      reason: "Check bidder balance after auction",
      assert: {
        type: AssertionInterfaceType.BALANCE,
        address: "0x1111111111111111111111111111111111111111" as Address,
        token: "0x0000000000000000000000000000000000000000" as Address,
        expected: "0"
      }
    }
  ]
};
```

## 🔧 Configuration

### Hardhat Configuration

The E2E tests use the main project's Hardhat configuration with the following key settings:

- **Solidity version**: 0.8.26
- **Optimizer**: Enabled with 200 runs
- **viaIR**: Enabled for complex contracts
- **Networks**: Hardhat local network with 20 test accounts

### Contract Integration

The test suite integrates with the real Foundry auction contracts:

- **`AuctionFactory`** - Deploys new auction instances
- **`Auction`** - The main auction contract
- **`WorkingCustomMockToken`** - Custom mock ERC20 tokens for testing
- **`USDCMock`** - Mock USDC token with 6 decimals

The test suite loads contract artifacts directly from Foundry's `out` directory, ensuring compatibility with the latest compiled contracts. The `forge build` command is automatically run before tests to ensure artifacts are up to date.

## 🧪 Writing Tests

### Creating a New Setup

1. Create a new TypeScript file in `instances/setup/` (e.g., `MySetup.ts`)
2. Import the `TestSetupData` and `Address` types from the schema
3. Define the auction parameters and environment with proper type annotations
4. Use `as Address` type assertions for 42-character hex addresses
5. Specify additional tokens to deploy
6. Set up initial balances for test accounts

### Creating a New Interaction

1. Create a new TypeScript file in `instances/interaction/` (e.g., `MyInteraction.ts`)
2. Import the `TestInteractionData` and `Address` types from the schema
3. Define bid scenarios with specific blocks and amounts
4. Add assertions (formerly checkpoints) to validate auction state
5. Use proper tick pricing for bid amounts
6. Use `as Address` type assertions for addresses

### Same-Block Transactions

The test suite supports multiple transactions in the same block, which is useful for testing:
- **MEV scenarios** - Transaction ordering and arbitrage opportunities
- **Gas optimization** - Multiple transactions hitting block gas limits
- **Real-world behavior** - True same-block execution like Ethereum

```typescript
{
  namedBidders: [
    {
      address: "0x111..." as Address,
      bids: [{ atBlock: 10, ... }]  // Same block
    },
    {
      address: "0x222..." as Address, 
      bids: [{ atBlock: 10, ... }]  // Same block
    }
  ],
  assertions: [
    {
      atBlock: 10,  // Same block - executes FIRST (queries before transactions)
      assert: {...}
    }
  ]
}
```

**Execution Order**: Queries/assertions execute before transactions in the same block.

### Expected Reverts

You can test that certain operations should fail by adding an `expectRevert` field to your bids:

```typescript
{
  atBlock: 10,
  amount: { side: "input", type: "raw", value: "1000000000000000000" },
  price: { type: "raw", value: "87150978765690771352898345369600" },
  expectRevert: "InsufficientBalance"
}
```

The `expectRevert` field accepts a string that should be contained in the revert data. The test will pass if the transaction reverts and the revert data contains the specified string.

### Adding Assertions

Assertions (formerly checkpoints) allow you to validate auction state at specific blocks. The E2E test suite supports multiple assertion types:

#### Available Assertion Types

- **`AssertionInterfaceType.BALANCE`** - Validate token or native currency balances
- **`AssertionInterfaceType.TOTAL_SUPPLY`** - Validate total supply of tokens
- **`AssertionInterfaceType.EVENT`** - Validate that specific events were emitted

#### Balance Assertions

```typescript
{
  atBlock: 20,
  reason: "Validate auction state",
  assert: {
    type: AssertionInterfaceType.BALANCE,
    address: "0x1111111111111111111111111111111111111111" as Address,
    token: "0x0000000000000000000000000000000000000000" as Address, // or token name
    expected: "0"
  }
}
```

#### Total Supply Assertions

```typescript
{
  atBlock: 20,
  reason: "Validate token supply",
  assert: {
    type: AssertionInterfaceType.TOTAL_SUPPLY,
    token: "SimpleToken", // or token address
    expected: "1000000000000000000000000"
  }
}
```

#### Event Assertions

```typescript
{
  atBlock: 20,
  reason: "Validate event emission",
  assert: {
    type: AssertionInterfaceType.EVENT,
    eventName: "BidPlaced",
    expectedArgs: {
      bidder: "0x1111111111111111111111111111111111111111",
      amount: "1000000000000000000"
    }
  }
}
```

## 🐛 Debugging

### Common Issues

1. **Tick Price Validation Errors** - Ensure floor price and tick spacing match the Foundry tests
2. **Balance Assertion Failures** - Check that expected balances account for bid amounts
3. **Contract Deployment Issues** - Verify that all required contracts are properly imported
4. **Expected Revert Failures** - Ensure the `expectRevert` string matches the actual revert data
5. **Native Currency Issues** - Use `0x0000000000000000000000000000000000000000` for native currency
6. **TypeScript Type Errors** - Use `as Address` type assertions for 42-character hex addresses
7. **Export Name Mismatches** - Ensure export names match the expected patterns (camelCase for PascalCase filenames)

### Enhanced Error Handling

The test suite now features centralized error messages and enhanced debugging:

- **🎯 Centralized Error Messages** - All error messages are defined in `src/constants.ts` for consistency
- **📊 Structured Error Context** - Error messages include relevant debugging informationtroubleshooting

### Debug Output

The test suite provides detailed logging:

- 🏗️ Auction deployment progress
- 🔍 Bid execution details with same-block grouping
- 💰 Balance validation results
- ✅ Assertion validation results
- 📊 Final auction state
- 📅 Block-by-block event execution

### Verbose Mode

Run tests with verbose output for more detailed information:

```bash
npx hardhat test test/e2e/tests/e2e.test.ts --verbose
```

## 📁 File Structure

```
test/e2e/
├── README.md                 # This file
├── src/                      # Core test components
│   ├── SchemaValidator.ts    # TypeScript instance loading
│   ├── AuctionDeployer.ts    # Contract deployment
│   ├── BidSimulator.ts       # Bid simulation
│   ├── AssertionEngine.ts    # Assertion validation
│   ├── SingleTestRunner.ts   # Test orchestration
│   ├── MultiTestRunner.ts    # Multi-test management
│   ├── E2ECliRunner.ts       # CLI interface
│   ├── constants.ts          # Centralized configuration and error messages
│   └── types.ts              # TypeScript type definitions
├── instances/                # Test data
│   ├── setup/               # Auction setup TypeScript files
│   │   └── SimpleSetup.ts
│   └── interaction/         # Interaction TypeScript files
│       └── SimpleInteraction.ts
├── schemas/                  # TypeScript interface definitions
│   ├── TestSetupSchema.ts    # Setup data interfaces with Address type
│   └── TestInteractionSchema.ts # Interaction data interfaces with Address type
├── tests/                    # Test files
│   └── e2e.test.ts          # Main E2E test
├── run-e2e-tests.sh         # Shell script for running tests
├── artifacts/                # Compiled contracts
└── cache/                    # Hardhat cache
```

## 🤝 Contributing

When adding new test scenarios:

1. Follow the existing TypeScript interface patterns
2. Use descriptive names for setup and interaction files (`.ts` extension)
3. Import the appropriate interfaces from `schemas/` directory
4. Use `as Address` type assertions for 42-character hex addresses
5. Add appropriate assertions to validate expected behavior
6. Test with both native currency (0x000...000) and ERC20 token currencies
7. Document any new assertion types or validation logic
8. Test same-block scenarios for MEV and gas optimization
9. Use the command-line interface for targeted testing
10. Ensure export names follow camelCase convention (e.g., `simpleSetup` for `SimpleSetup.ts`)

### Adding New Combinations

To add new test combinations, edit `test/e2e/src/E2ECliRunner.ts`:

```typescript
const COMBINATIONS_TO_RUN = [
  { setup: 'SimpleSetup.ts', interaction: 'SimpleInteraction.ts' },
  { setup: 'MySetup.ts', interaction: 'MyInteraction.ts' },  // Add new combinations
  // Only add compatible combinations!
];
```

**Important**: Only add combinations that are compatible (same tokens, currencies, etc.).

## 📚 Related Documentation

- [Foundry Test Documentation](../test/README.md)
- [Auction Contract Interface](../../src/interfaces/IAuction.sol)
- [Hardhat Configuration](../../hardhat.config.ts)
