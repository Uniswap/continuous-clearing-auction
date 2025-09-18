# TWAP Auction E2E Test Suite

This directory contains the end-to-end (E2E) test suite for the TWAP Auction system. The test suite allows you to define complex auction scenarios using JSON schemas and validate the entire auction lifecycle from deployment to completion.

## 🚧 TODO: Unimplemented Features

The following features are defined in the schemas but not yet implemented. These represent the roadmap for expanding the e2e test capabilities:

### 🎯 Bid System Enhancements
- **Recurring Bids** - Support for `recurringBids` with `startBlock`, `intervalBlocks`, `occurrences`
- **Growth Factors** - `amountFactor` and `priceFactor` for recurring bid progression
- **Amount Variations** - Random sampling for amount and price variations
- **Advanced Amount Types**:
  - `percentOfSupply` - Calculate percentage of total token supply
  - `basisPoints` - Calculate basis points (1/10000) of total supply
  - `percentOfGroup` - Calculate percentage of group total

### Allow arbitary addresses to start auctions

### 🔄 Transfer Actions
- **Token Transfers** - Execute transfers between addresses during test execution
- **Multi-Token Support** - Handle both ERC20 tokens and native currency transfers
- **Label Resolution** - Resolve symbolic labels to concrete addresses for transfer destinations

### 📊 Advanced Assertions
- **Event Assertions** - Validate that specific events were emitted during execution
- **Pool State Assertions** - Check tick, sqrtPriceX96, and liquidity values
- **Complex State Validation** - Beyond current balance checking capabilities

### 🌐 Environment Configuration
- **Chain Configuration** - `chainId`, `blockTimeSec`, `blockGasLimit`, `txGasLimit`
- **Gas Management** - `baseFeePerGasWei` configuration
- **Fork Support** - `rpcUrl` and `blockNumber` for testing against specific blockchain states

### 🔧 Infrastructure Improvements
- **Enhanced Error Handling** - Better error messages and debugging capabilities
- **Performance Optimization** - Parallel execution and caching improvements

---

*These features are documented with TODO comments throughout the codebase. Each TODO includes implementation guidance and context.*

## ✨ Key Features

- **🎯 Targeted Testing** - Run only compatible setup/interaction combinations
- **⚡ Same-Block Execution** - Multiple transactions in the same block with query priority
- **📊 Comprehensive Logging** - Detailed execution traces and state information
- **🛠️ Flexible Interface** - npm scripts, command-line options, and shell scripts
- **🔍 Real Contract Integration** - Uses actual Foundry auction contracts, not mocks
- **📋 Schema Validation** - JSON schema validation for test configuration
- **🎮 MEV Testing** - Test transaction ordering and arbitrage scenarios

## 🏗️ Architecture

The E2E test suite is built on top of Hardhat and consists of several key components:

### Core Components

- **`src/SchemaValidator.ts`** - Loads and validates JSON schemas
- **`src/AuctionDeployer.ts`** - Deploys auction contracts and sets up the environment
- **`src/BidSimulator.ts`** - Simulates bids and interactions with the auction
- **`src/AssertionEngine.ts`** - Validates checkpoints and assertions
- **`src/SingleTestRunner.ts`** - Orchestrates the complete test execution
- **`src/MultiTestRunner.ts`** - Manages multiple test combinations
- **`src/E2ECliRunner.ts`** - Command-line interface for running specific combinations

### Test Data

- **`instances/setup/`** - JSON files defining auction setup parameters
- **`instances/interaction/`** - JSON files defining bid scenarios and interactions
- **`schemas/`** - JSON schemas for validating setup and interaction files

## 🔄 Execution Flow

The test suite follows a structured execution flow:

1. **📋 Schema Validation** - Validate setup and interaction JSON files
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
./script/test/run-e2e-tests.sh
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
npx ts-node test/e2e/src/E2ECliRunner.ts --setup simple-setup.json --interaction simple-interaction.json

# Show help
npx ts-node test/e2e/src/E2ECliRunner.ts --help

# Verbose output
./script/test/run-e2e-tests.sh --verbose
```

## 📋 Test Structure

### Setup Schema

The setup schema defines the auction environment:

```json
{
  "env": {
    "chainId": 31337,
    "startBlock": "1",
    "balances": [
      {
        "address": "0x1111111111111111111111111111111111111111",
        "token": "0x0000000000000000000000000000000000000000",
        "amount": "1000000000000000000000"
      }
    ]
  },
  "auctionParameters": {
    "currency": "0x0000000000000000000000000000000000000000",
    "auctionedToken": "SimpleToken",
    "tokensRecipient": "0x2222222222222222222222222222222222222222",
    "fundsRecipient": "0x3333333333333333333333333333333333333333",
    "startOffsetBlocks": 0,
    "auctionDurationBlocks": 50,
    "claimDelayBlocks": 10,
    "graduationThresholdMps": "1000",
    "tickSpacing": 100,
    "validationHook": "0x0000000000000000000000000000000000000000",
    "floorPrice": "79228162514264337593543950336000"
  },
  "additionalTokens": [
    {
      "name": "SimpleToken",
      "decimals": "18",
      "totalSupply": "1000000000000000000000000",
      "percentAuctioned": "10"
    }
  ]
}
```

### Interaction Schema

The interaction schema defines bid scenarios and checkpoints:

```json
{
  "timeBase": "auctionStart",
  "namedBidders": [
    {
      "address": "0x1111111111111111111111111111111111111111",
      "label": "SimpleBidder",
      "bids": [
        {
          "atBlock": 10,
          "amount": { "side": "input", "type": "raw", "value": "1000000000000000000" },
          "price": { "type": "raw", "value": "87150978765690771352898345369600" },
          "expectRevert": "InsufficientBalance"
        }
      ]
    }
  ],
  "checkpoints": [
    {
      "atBlock": 20,
      "reason": "Check bidder balance after auction",
      "assert": {
        "type": "balance",
        "address": "0x1111111111111111111111111111111111111111",
        "token": "0x0000000000000000000000000000000000000000",
        "expected": "0"
      }
    }
  ]
}
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

1. Create a new JSON file in `instances/setup/`
2. Define the auction parameters and environment
3. Specify additional tokens to deploy
4. Set up initial balances for test accounts

### Creating a New Interaction

1. Create a new JSON file in `instances/interaction/`
2. Define bid scenarios with specific blocks and amounts
3. Add checkpoints to validate auction state
4. Use proper tick pricing for bid amounts

### Same-Block Transactions

The test suite supports multiple transactions in the same block, which is useful for testing:
- **MEV scenarios** - Transaction ordering and arbitrage opportunities
- **Gas optimization** - Multiple transactions hitting block gas limits
- **Real-world behavior** - True same-block execution like Ethereum

```json
{
  "namedBidders": [
    {
      "address": "0x111...",
      "bids": [{"atBlock": 10, ...}]  // Same block
    },
    {
      "address": "0x222...", 
      "bids": [{"atBlock": 10, ...}]  // Same block
    }
  ],
  "checkpoints": [
    {
      "atBlock": 10,  // Same block - executes FIRST (queries before transactions)
      "assert": {...}
    }
  ]
}
```

**Execution Order**: Queries/checkpoints execute before transactions in the same block.

### Expected Reverts

You can test that certain operations should fail by adding an `expectRevert` field to your bids:

```json
{
  "atBlock": 10,
  "amount": { "side": "input", "type": "raw", "value": "1000000000000000000" },
  "price": { "type": "raw", "value": "87150978765690771352898345369600" },
  "expectRevert": "InsufficientBalance"
}
```

The `expectRevert` field accepts a string that should be contained in the revert data. The test will pass if the transaction reverts and the revert data contains the specified string.

### Adding Checkpoints

Checkpoints allow you to validate auction state at specific blocks:

```json
{
  "atBlock": 20,
  "reason": "Validate auction state",
  "assert": {
    "type": "balance",
    "address": "0x1111111111111111111111111111111111111111",
    "token": "ETH",
    "expected": "0"
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

### Debug Output

The test suite provides detailed logging:

- 🏗️ Auction deployment progress
- 🔍 Bid execution details with same-block grouping
- 💰 Balance validation results
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
├── hardhat.config.ts         # Hardhat configuration
├── src/                      # Core test components
│   ├── SchemaValidator.ts    # Schema validation
│   ├── AuctionDeployer.ts    # Contract deployment
│   ├── BidSimulator.ts       # Bid simulation
│   ├── AssertionEngine.ts    # Checkpoint validation
│   ├── SingleTestRunner.ts   # Test orchestration
│   ├── MultiTestRunner.ts    # Multi-test management
│   └── E2ECliRunner.ts       # CLI interface
├── instances/                # Test data
│   ├── setup/               # Auction setup schemas
│   └── interaction/         # Interaction schemas
├── schemas/                  # JSON validation schemas
│   ├── testSetupSchema.json
│   └── tokenInteractionSchema.json
├── tests/                    # Test files
│   └── e2e.test.ts          # Main E2E test
├── artifacts/                # Compiled contracts
└── cache/                    # Hardhat cache
```

## 🤝 Contributing

When adding new test scenarios:

1. Follow the existing JSON schema patterns
2. Use descriptive names for setup and interaction files
3. Add appropriate checkpoints to validate expected behavior
4. Test with both ETH and ERC20 token currencies
5. Document any new assertion types or validation logic
6. Test same-block scenarios for MEV and gas optimization
7. Use the command-line interface for targeted testing

### Adding New Combinations

To add new test combinations, edit `test/e2e/src/E2ECliRunner.ts`:

```javascript
const COMBINATIONS_TO_RUN = [
  { setup: 'simple-setup.json', interaction: 'simple-interaction.json' },
  { setup: 'setup02.json', interaction: 'interaction02.json' },  // Add new combinations
  // Only add compatible combinations!
];
```

**Important**: Only add combinations that are compatible (same tokens, currencies, etc.).

## 📚 Related Documentation

- [Foundry Test Documentation](../test/README.md)
- [Auction Contract Interface](../../src/interfaces/IAuction.sol)
- [Hardhat Configuration](../../hardhat.config.ts)
