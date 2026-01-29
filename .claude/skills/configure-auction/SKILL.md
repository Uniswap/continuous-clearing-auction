---
name: configure-auction
description: Interactive form to configure CCA auction parameters.
---

# Objective

You will guide the user through an interactive form to fill out the auction configuration file at `script/example.json`. This file is used to configure the auction parameters for a CCA smart contract deployment.

## Constants and validation rules
- Block times are 12s on mainnet and sepolia, 2s on base and other L2s (unichain, arbitrum, optimism) as well as their testnets. 
- Enforce the following invariant: startBlock < endBlock <= claimBlock
- Assume token decimals are 18 unless otherwise specified.
- Ensure addresses are valid Ethereum addresses (0x followed by 40 hex chars)
- Ensure numeric values are non-negative
- Price is in Q96 format, with 79228162514264337593543950336 representing a price ratio of 1:1.
- Tick spacing is also in Q96 form, and the floor price must be a multiple of the tick spacing. You may have to round the floor price a little bit down to make it a multiple of the tick spacing. For example, if we want a tick spacing of 1% of the floor price, round the last two digits to 00.
- Use the `generate_supply_schedule.py` script to generate the supply schedule.

## Tools

### Supply Schedule Generator
Use the standalone script `generate_supply_schedule.py` in this directory to generate supply schedules:
```bash
python3 generate_supply_schedule.py <auction_blocks> [--prebid <prebid_blocks>] --pretty
```

This script applies the standard percentage distribution (1.26%, 1.56%, ..., 30.43% final block) to any auction duration.

### Floor Price and Tick Spacing Calculations
Use these documented formulas:
```bash
# Floor price calculation (Q96 format)
# Base value: 79228162514264337593543950336 (represents 1:1 ratio)
floorPrice = base_value * ratio  # e.g., * 0.1 for 0.1x ratio

# Tick spacing calculation
tickSpacing = floor(floorPrice * percentage)  # e.g., * 0.01 for 1%

# Round floor price to multiple of tick spacing
roundedFloorPrice = floor(floorPrice / tickSpacing) * tickSpacing
```

### Public RPCs
You have the following public RPCs available to get current block numbers:
- Base: https://mainnet.base.org
- Mainnet: https://ethereum-rpc.publicnode.com
- Sepolia: https://ethereum-sepolia-rpc.publicnode.com
- Unichain: https://unichain-rpc.publicnode.com

Example RPC call to get the current block number:
```bash
curl -X POST "<RPC_URL>" \
  -H "Content-Type: application/json" \
  -d '{
  "jsonrpc": "2.0",
  "method": "eth_blockNumber",
  "params": [],
  "id": 1
}'
```

## Conversation rules
- Ask and give at most two options, allowing the user to select the correct option or fill in a value manually as the third select. A selection should always end up with a value, never another question. For example, if the user is asked to select a chain, the user should select the correct chain or fill in the chain ID manually.


## Process:

1. **Read the current example.json** to see if there are any existing values

2. **Use AskUserQuestion to collect the following information step by step:**

   **Basic Configuration:**
   - Chain ID (e.g., 1 for Ethereum mainnet, 8453 for Base)
   - Token address (the token being auctioned)
   - Total supply to auction (in wei/smallest unit)
   - Currency address (the token used to purchase, e.g., USDC). Use address(0) for Native.
   - Tokens recipient address (where unsold tokens go) - allow user to enter address or skip (use empty string/"REPLACE_BEFORE_DEPLOYMENT")
   - Funds recipient address (where raised funds go) - allow user to enter address or skip (use empty string/"REPLACE_BEFORE_DEPLOYMENT")

   **Block Configuration:**
   - CONTEXT: all configuration can be done in blocks or datetime. If datetime is provided, convert it to blocks using the block time table. Assume all datetime values are relative to the local system time zone.
   - Ask if they want a prebid period (optional)
        - If yes, ask for "Prebid duration"
   - Start block (when auction starts)
   - End block (when auction ends)
   - Claim block (when tokens can be claimed)

   **Auction Parameters:**
   - Floor price (minimum price)
   - Tick spacing (in percentage of floor price)
   - Validation hook address (use 0x0000000000000000000000000000000000000000 if none)
   - Required currency raised (minimum funds needed, 0 if no minimum)

   **Supply Schedule:**
   - Ask if they want a prebid period (optional). If yes, this will have mps of 0 with the duration specified in blocks.
   - Next, ask if they want to use the standard supply schedule or a custom one. If standard, use the standard schedule referenced in the [constants and validation rules](#constants-and-validation-rules) section above.

3. **Build the JSON structure** with the collected information

4. **Write the updated JSON** to a file in the `script` directory. Ask user to either overwrite example.json or enter a custom filename directly (single-step, no intermediate choice).

5. **Display a summary** of the configuration to the user

## Important Notes:
- Use AskUserQuestion to make the form interactive and user-friendly
- Provide helpful descriptions for each field in the question options
- Format the JSON output with proper indentation
- Preserve scientific notation for large numbers where appropriate (e.g., 1e29)
- Use the `generate_supply_schedule.py` script for supply schedule generation
- Use the documented formulas for floor price and tick spacing calculations

## Example supplySchedule structure:
If prebid duration is 43200 blocks:
```json
"supplySchedule": [
  { "mps": 0, "blockDelta": 43200 }
]
```

Sample response from calling `generate_supply_schedule.py` with block duration of 86400 (2 days, 2 second blocks (base, L2s)) blocks:
```json
[{"mps": 42, "blockDelta": 3000}, {"mps": 52, "blockDelta": 3000}, {"mps": 59, "blockDelta": 3400}, {"mps": 64, "blockDelta": 4400}, {"mps": 69, "blockDelta": 5200}, {"mps": 73, "blockDelta": 6000}, {"mps": 77, "blockDelta": 7000}, {"mps": 81, "blockDelta": 7800}, {"mps": 85, "blockDelta": 9600}, {"mps": 88, "blockDelta": 10000}, {"mps": 92, "blockDelta": 12000}, {"mps": 95, "blockDelta": 14999}, {"mps": 3043295, "blockDelta": 1}]
```

Sample response from calling `generate_supply_schedule.py` with block duration of 14400 blocks (2 days, 12 second blocks (mainnet)):
```json
[{"mps": 42, "blockDelta": 3000}, {"mps": 52, "blockDelta": 3000}, {"mps": 59, "blockDelta": 3400}, {"mps": 64, "blockDelta": 4400}, {"mps": 69, "blockDelta": 5200}, {"mps": 73, "blockDelta": 6000}, {"mps": 77, "blockDelta": 7000}, {"mps": 81, "blockDelta": 7800}, {"mps": 85, "blockDelta": 9600}, {"mps": 88, "blockDelta": 10000}, {"mps": 92, "blockDelta": 12000}, {"mps": 95, "blockDelta": 14999}, {"mps": 3043295, "blockDelta": 1}]
```
