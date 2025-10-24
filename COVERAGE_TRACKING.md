# Combinatorial Test Coverage Tracking

## Overview

This system tracks which test scenarios are being covered during combinatorial fuzz testing. It helps identify coverage gaps and understand the distribution of test cases across different scenarios.

## How It Works

1. **During Test Execution**: The `documentState()` function is called after each successful test verification
2. **Data Collection**: Test parameters (PreBid scenario, PostBid scenario, bid amount, max price) are written to `coverage_data.csv`
3. **Analysis**: Run the Python script to generate a comprehensive coverage report

## Usage

### Run Tests and Collect Coverage Data

```bash
# Delete old coverage data
rm -f coverage_data.csv

# Run tests with desired number of fuzz runs
forge test --match-test testFuzz_CombinatorialExploration --fuzz-runs 100

# The coverage_data.csv file is now populated
```

### Analyze Coverage

```bash
python3 analyze_csv_coverage.py coverage_data.csv
```

## What Gets Tracked

### Scenarios

**Pre-Bid Scenarios** (4 types):
- `NoBidsBeforeUser` (0): No other bids exist before user's bid
- `BidsBeforeUser` (1): Other bids exist before user's bid
- `ClearingPriceBelowMaxPrice` (2): Clearing price is below the max price before bidding
- `BidsAtClearingPrice` (3): Bids exist exactly at the clearing price

**Post-Bid Scenarios** (5 types):
- `NoBidsAfterUser` (0): No bids placed after user's bid
- `UserAboveClearing` (1): User's bid remains above clearing price
- `UserAtClearing` (2): User's bid is at the clearing price
- `UserOutbidLater` (3): User gets outbid after some time
- `UserOutbidImmediately` (4): User gets outbid immediately

**Total Possible Combinations**: 4 × 5 = 20

### Bid Parameters

- **Bid Amount**: The amount of currency bid (in wei)
- **Max Price**: The maximum price willing to pay (in Q96 fixed-point format)

## Coverage Report Sections

### 1. Scenario Coverage
Lists all tested scenario combinations with their occurrence counts.

### 2. Bid Amount Statistics
- Min, max, and average bid amounts across all tests
- Helps understand the range of bid values being tested

### 3. Max Price Statistics
- Min, max, and average max prices
- Shows the distribution of price points

### 4. Coverage Gaps
Identifies which of the 20 possible scenario combinations are missing from the test runs.

### 5. Scenario Distribution
Shows how evenly distributed the tests are across:
- Pre-bid scenarios
- Post-bid scenarios

Includes visual bar charts for quick assessment.

### 6. Scenario Combination Heatmap
Matrix view showing the count for each (PreBid × PostBid) combination.

## Interpreting Results

### Good Coverage
- All or most of the 20 combinations are covered
- Reasonable distribution across scenarios (not heavily skewed)
- Wide range of bid amounts and prices tested

### Coverage Gaps to Address
If certain combinations are missing:
- Some scenarios might be mutually exclusive (this is expected)
- Increase fuzz runs to hit rare combinations
- Adjust helper functions if certain combinations should be possible but aren't being generated

## Example Output

```
Total Test Cases: 510

Missing 2/20 scenario combinations:
  • ClearingPriceBelowMaxPrice + UserAboveClearing
  • BidsAtClearingPrice + UserAboveClearing

Pre-Bid Scenario Distribution:
  NoBidsBeforeUser                      120 ( 23.5%) ███████████
  BidsBeforeUser                        123 ( 24.1%) ████████████
  ...
```

## Files

- `test/combinatorial/Auction.submitBid.combinatorial.t.sol`: Test file with `documentState()` function
- `coverage_data.csv`: Generated CSV file with test data (gitignored)
- `analyze_csv_coverage.py`: Analysis script
- `foundry.toml`: Updated with file write permissions for `./`

## Notes

- **The CSV file APPENDS data** - Running tests multiple times accumulates coverage data across runs
- To start fresh, delete the CSV file before running: `rm -f coverage_data.csv`
- Large fuzz run counts will generate large CSV files
- The `documentState()` function has minimal stack impact as it's separate from verification logic

## Accumulating Coverage Data

The system automatically **appends** new test data to the CSV file. This is useful for:

1. **Building coverage over multiple sessions**
   ```bash
   # Run 1
   forge test --match-test testFuzz_CombinatorialExploration --fuzz-runs 50
   # CSV now has ~1000 entries

   # Run 2 (appends to existing data)
   forge test --match-test testFuzz_CombinatorialExploration --fuzz-runs 50
   # CSV now has ~2000 entries

   # Analyze combined coverage
   python3 analyze_csv_coverage.py coverage_data.csv
   ```

2. **Testing with different configurations**
   ```bash
   # Test with one configuration
   forge test --match-test testFuzz_CombinatorialExploration --fuzz-runs 100

   # Modify helper functions or scenarios
   # ... make changes ...

   # Run again to add new coverage patterns
   forge test --match-test testFuzz_CombinatorialExploration --fuzz-runs 100

   # Analyze aggregate coverage
   python3 analyze_csv_coverage.py coverage_data.csv
   ```

3. **Starting fresh**
   ```bash
   # Delete old data
   rm -f coverage_data.csv

   # Run new tests
   forge test --match-test testFuzz_CombinatorialExploration --fuzz-runs 200
   ```
