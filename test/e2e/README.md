# TWAP Auction End-to-End Test Suite

This directory contains a comprehensive end-to-end test suite for the TWAP Auction system using Hardhat.

## Structure

```
test/e2e/
├── package.json              # Dependencies and scripts
├── hardhat.config.js         # Hardhat configuration
├── src/                      # Core test framework
│   ├── TestRunner.js         # JSON schema validation and test orchestration
│   ├── AuctionDeployer.js    # Auction deployment utilities
│   ├── BidSimulator.js       # Bid execution and simulation
│   └── AssertionEngine.js    # Checkpoint validation and assertions
├── tests/                    # Test files
│   ├── SetupTests.js         # Auction setup validation tests
│   └── InteractionTests.js   # Bid interaction and flow tests
├── instances/                # Test data instances
│   ├── setup/                # Auction setup configurations
│   └── interaction/          # Bid interaction scenarios
└── schemas/                  # JSON schemas for validation
    ├── testSetupSchema.json
    └── tokenInteractionSchema.json
```

## Features

- **JSON Schema Validation**: Validates test instances against schemas
- **Flexible Test Data**: Supports named bidders, group bidders, and complex scenarios
- **Block-based Timing**: Precise control over when actions occur
- **Checkpoint Validation**: Assertions at specific points in the auction
- **Admin Actions**: Support for sweep operations and other admin functions
- **Transfer Actions**: Token transfers between addresses during auction

## Usage

1. **Install dependencies**:
   ```bash
   cd test/e2e
   npm install
   ```

2. **Run all tests**:
   ```bash
   npm test
   ```

3. **Run specific test suites**:
   ```bash
   npm run test:setup        # Setup validation tests only
   npm run test:interaction  # Interaction flow tests only
   npm run test:combined     # Combined setup + interaction tests
   npm run test:all          # All test suites
   ```

## Test Flow

The framework uses a **two-phase approach**:

1. **Setup Phase** (`instances/setup/`):
   - Defines auction parameters (currency, recipients, timing, etc.)
   - Configures environment (chain, balances, forking)
   - Creates the auction contract with specified parameters

2. **Interaction Phase** (`instances/interaction/`):
   - Defines bid scenarios (named bidders, groups, timing)
   - Specifies actions (transfers, admin operations)
   - Sets validation checkpoints and assertions
   - **Checkpoints are validated at their specific blocks during execution**

**Example**: `setup01.json` + `interaction01.json` creates an auction with specific parameters, then tests a complex bidding scenario with multiple participants and checkpoints.

## Test Data Format

### Setup Instances (`instances/setup/`)
Define auction parameters, environment configuration, and token details.

### Interaction Instances (`instances/interaction/`)
Define bid scenarios, timing, and validation checkpoints.

## Key Components

- **TestRunner**: Orchestrates test execution and validates JSON schemas
- **AuctionDeployer**: Handles auction creation and parameter setup
- **BidSimulator**: Executes bids according to interaction specifications
- **AssertionEngine**: Validates checkpoints and auction state

## Adding New Tests

1. Create new JSON instances in `instances/setup/` or `instances/interaction/`
2. Add corresponding test cases in the test files
3. Extend the framework classes as needed for new functionality

## Schema Validation

All test instances are validated against JSON schemas to ensure:
- Required fields are present
- Data types are correct
- Values are within valid ranges
- References are properly formatted
