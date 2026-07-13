# Combinatorial Test Coverage Tracking

## Overview

This system tracks which test scenarios are covered during combinatorial fuzz testing. It collects detailed metrics about auction outcomes, bid behavior, and scenario distributions to help identify coverage gaps and understand test patterns.

## Quick Start

### 1. Run Tests and Collect Coverage Data

```bash
# Delete old coverage data (optional, starts fresh)
rm -f coverage_data.csv

# Run tests with desired number of fuzz runs
forge test --match-test testFuzz_CombinatorialExploration --fuzz-runs 100
```

### 2. Analyze Coverage

```bash
# View report in terminal
python3 analyze_csv_coverage.py coverage_data.csv

# Save report to file
python3 analyze_csv_coverage.py coverage_data.csv > report.txt
```

## CSV Data Format

The coverage data CSV contains **22 columns** capturing comprehensive test metrics:

### Core Columns (1-4)
1. **preBidScenario** - Pre-bid scenario enum (0-3)
2. **postBidScenario** - Post-bid scenario enum (0-4)
3. **bidAmount** - Bid amount in wei
4. **maxPrice** - Maximum price in Q96 format

### Fill Ratio Metrics (5-6)
5. **fillRatioMPS** - Fill ratio using MPS precision (0-10,000,000 where 10,000,000 = 100%)
6. **partialFillReason** - "full", "non_graduated", "partial_graduated", or "partial_outbid"

### Timing Metrics (7-9)
7. **bidLifetimeBlocks** - Blocks from bid start to exit
8. **blocksFromStart** - Blocks from auction start to bid submission
9. **timeToOutbid** - Blocks until bid was outbid (0 if never outbid)

### Status Flags (10-12)
10. **wasOutbid** - Boolean: bid was outbid by another bid
11. **neverFullyFilled** - Boolean: fill ratio < 100%
12. **nearGraduationBoundary** - Boolean: within last 10% of auction duration

### Price Analysis (13-14)
13. **clearingPriceStart** - Clearing price when bid started
14. **clearingPriceEnd** - Clearing price at auction end

### Token Outcomes (15-16)
15. **tokensReceived** - Tokens received in wei
16. **pricePerTokenETH** - Price paid per token in ETH (wei)

### Graduation Tracking (17)
17. **didGraduate** - Boolean: auction graduated

### Auction Context (18-22)
18. **auctionStartBlock** - Block number when auction started
19. **auctionDurationBlocks** - Total auction duration
20. **floorPrice** - Auction floor price in Q96 format
21. **tickSpacing** - Tick spacing in Q96 format
22. **totalSupply** - Token total supply in wei

## Test Scenarios

### Pre-Bid Scenarios (4 types)
- `NoBidsBeforeUser` (0): No other bids exist before user's bid
- `BidsBeforeUser` (1): Other bids exist before user's bid
- `ClearingPriceBelowMaxPrice` (2): Clearing price is below the max price before bidding
- `BidsAtClearingPrice` (3): Bids exist exactly at the clearing price

### Post-Bid Scenarios (5 types)
- `NoBidsAfterUser` (0): No bids placed after user's bid
- `UserAboveClearing` (1): User's bid remains above clearing price
- `UserAtClearing` (2): User's bid is at the clearing price
- `UserOutbidLater` (3): User gets outbid after some time
- `UserOutbidImmediately` (4): User gets outbid immediately

**Total Possible Combinations**: 4 × 5 = 20

## Accumulating Coverage Data

The system automatically **appends** new test data to the CSV file. This allows building coverage over multiple sessions:

```bash
# Run 1
forge test --match-test testFuzz_CombinatorialExploration --fuzz-runs 50
# CSV now has data from run 1

# Run 2 (appends to existing data)
forge test --match-test testFuzz_CombinatorialExploration --fuzz-runs 50
# CSV now has combined data from both runs

# Analyze combined coverage
python3 analyze_csv_coverage.py coverage_data.csv
```

To start fresh, delete the CSV file before running: `rm -f coverage_data.csv`

## Report Organization

The analysis script generates a comprehensive report organized as follows:

1. **Auction-Level Metrics** - Context, graduation rates, token outcomes
2. **Bid-Level Metrics** - Fill ratios, timing, bid patterns
3. **Parameter Statistics** - Bid amounts and max prices
4. **Scenario Analysis** - Coverage tables, distributions, heatmaps, gaps

## Important Notes

### Fill Ratio Precision
- Fill ratios use **MPS (Milli-Per-Second) precision**: 1e7 = 10,000,000 = 100%
- Example: 5,000,000 MPS = 50.00000%
- Provides 5 decimal place precision for accurate partial fill tracking

### Data Accumulation
- CSV file APPENDS data across test runs
- Delete `coverage_data.csv` to start fresh
- Large fuzz run counts generate large CSV files

### Compilation
- The combinatorial test file uses `via_ir` compilation to handle stack depth
- Other test files use `via_ir = false` for faster compilation
- See `foundry.toml` for compilation_restrictions details

### File Write Permissions
- `foundry.toml` is configured with file write permissions for `./`
- This allows the test to write `coverage_data.csv` to the project root

## Files

- `test/combinatorial/Auction.submitBid.combinatorial.t.sol` - Main test file with coverage collection
- `test/combinatorial/CombinatorialHelpers.sol` - Helper functions for scenario setup
- `coverage_data.csv` - Generated CSV file with test data (gitignored)
- `analyze_csv_coverage.py` - Python analysis script
- `report.txt` - Generated coverage report (optional)
- `foundry.toml` - Forge configuration with file write permissions

## Interpreting Results

### Good Coverage Indicators
- All or most of the 20 scenario combinations are covered
- Reasonable distribution across scenarios (not heavily skewed)
- Wide range of bid amounts and prices tested
- Diverse fill ratio distribution (not clustering at 0% or 100%)

### Coverage Gaps
If certain combinations are missing:
- Some scenarios might be mutually exclusive (expected)
- Increase fuzz runs to hit rare combinations
- Adjust helper functions if combinations should be possible but aren't generated

### Understanding Missing Combinations
Some scenario combinations may be impossible due to the auction mechanics. For example, if the clearing price is already below the user's max price before bidding, the user's bid will typically be above clearing after submission, making certain post-bid scenarios unlikely or impossible.
