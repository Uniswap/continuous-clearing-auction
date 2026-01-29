#!/usr/bin/env python3
"""
Generate supply schedule for CCA auction.

This script takes an auction duration and generates a supply schedule based on
the standard percentage distribution. The standard schedule follows a moderate
convex curve (exponent ~1.2) and allocates ~30% to the final block.

Standard percentage schedule (always the same):
    Phase 1:  1.26%
    Phase 2:  1.56%
    Phase 3:  2.006%
    Phase 4:  2.816%
    Phase 5:  3.588%
    Phase 6:  4.38%
    Phase 7:  5.39%
    Phase 8:  6.318%
    Phase 9:  8.16%
    Phase 10: 8.8%
    Phase 11: 11.04%
    Phase 12: 14.24905%
    Phase 13: 30.43295% (final block)

Usage:
    python generate_supply_schedule.py <auction_blocks> [--prebid <prebid_blocks>]

Example:
    python generate_supply_schedule.py 86400 --prebid 10800
"""

import argparse
import json
import sys


# Standard percentage schedule (fixed)
STANDARD_PHASES = [
    (0.0126, 3000),      # 1.26%
    (0.0156, 3000),      # 1.56%
    (0.02006, 3400),     # 2.006%
    (0.02816, 4400),     # 2.816%
    (0.03588, 5200),     # 3.588%
    (0.0438, 6000),      # 4.38%
    (0.0539, 7000),      # 5.39%
    (0.06318, 7800),     # 6.318%
    (0.0816, 9600),      # 8.16%
    (0.088, 10000),      # 8.8%
    (0.1104, 12000),     # 11.04%
    (0.1424905, 14999),  # 14.24905%
    (0.3043295, 1),      # 30.43295% (final block)
]

# Target total supply in mps units
TOTAL_TARGET = 10_000_000  # 1e7


def generate_schedule(auction_blocks: int, prebid_blocks: int = 0) -> list:
    """
    Generate supply schedule for the given auction duration.

    Args:
        auction_blocks: Total number of blocks for the auction
        prebid_blocks: Number of blocks for prebid period (0 mps)

    Returns:
        List of dicts with 'mps' and 'blockDelta' keys
    """
    schedule = []

    # Add prebid period if specified
    if prebid_blocks > 0:
        schedule.append({"mps": 0, "blockDelta": prebid_blocks})

    # Calculate mps for each phase
    total_allocated = 0

    for i, (pct, blocks) in enumerate(STANDARD_PHASES):
        # Calculate tokens for this phase
        tokens = int(pct * TOTAL_TARGET)

        # Calculate mps (tokens per block)
        mps = tokens // blocks
        actual_allocated = mps * blocks

        # For all phases except the last, add normally
        if i < len(STANDARD_PHASES) - 1:
            total_allocated += actual_allocated
            schedule.append({"mps": mps, "blockDelta": blocks})
        else:
            # Last phase gets remainder to ensure exact total
            remainder = TOTAL_TARGET - total_allocated
            schedule.append({"mps": remainder, "blockDelta": 1})

    return schedule


def main():
    parser = argparse.ArgumentParser(
        description="Generate supply schedule for CCA auction",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__
    )
    parser.add_argument(
        "auction_blocks",
        type=int,
        help="Total number of blocks for the auction"
    )
    parser.add_argument(
        "--prebid",
        type=int,
        default=0,
        help="Number of blocks for prebid period (default: 0)"
    )
    parser.add_argument(
        "--pretty",
        action="store_true",
        help="Pretty-print the JSON output"
    )

    args = parser.parse_args()

    # Validate inputs
    if args.auction_blocks <= 0:
        print("Error: auction_blocks must be positive", file=sys.stderr)
        sys.exit(1)

    if args.prebid < 0:
        print("Error: prebid blocks cannot be negative", file=sys.stderr)
        sys.exit(1)

    # Generate schedule
    schedule = generate_schedule(args.auction_blocks, args.prebid)

    # Output as JSON
    if args.pretty:
        print(json.dumps(schedule, indent=2))
    else:
        print(json.dumps(schedule))


if __name__ == "__main__":
    main()
