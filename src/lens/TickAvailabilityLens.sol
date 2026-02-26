// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IContinuousClearingAuction} from '../interfaces/IContinuousClearingAuction.sol';
import {Tick} from '../interfaces/ITickStorage.sol';
import {FixedPoint96} from '../libraries/FixedPoint96.sol';

/// @notice The availability of tokens at a given tick
struct TickAvailability {
    uint256 price;
    uint256 currencyDemandQ96;
    uint256 cumulativeDemandAboveQ96;
    uint256 tokensAvailable;
}

/// @dev Scratch data for initialized ticks used by getTickAvailabilityFull
struct InitTickData {
    uint256 count;
    uint256[2048] prices;
    uint256[2048] demands;
    uint256[2048] cumulativeAbove;
}

/// @title TickAvailabilityLens
/// @notice Lens contract for computing how many tokens are still available for sale at each tick
contract TickAvailabilityLens {
    /// @notice Maximum number of initialized ticks supported in a single query
    uint256 private constant MAX_TICKS = 2048;

    /// @notice Maximum number of results returned per page for getTickAvailabilityFull
    uint256 private constant MAX_RESULT = 10_000;

    /// @notice Sentinel value for the next pointer of the highest tick in the book
    uint256 private constant MAX_TICK_PTR = type(uint256).max;

    /// @notice Computes the token availability at each initialized tick in the auction
    /// @param auction The auction to query
    /// @return result An array of TickAvailability structs, ordered from lowest to highest price
    function getTickAvailability(IContinuousClearingAuction auction)
        external
        view
        returns (TickAvailability[] memory result)
    {
        uint256 floor = auction.floorPrice();
        uint128 totalSupply = auction.totalSupply();
        // Phase 1: Walk the linked list from floor, collecting all initialized ticks
        uint256[MAX_TICKS] memory prices;
        uint256[MAX_TICKS] memory demands;
        uint256 count;

        uint256 currentPrice = floor;
        while (currentPrice != MAX_TICK_PTR && count < MAX_TICKS) {
            Tick memory tick = auction.ticks(currentPrice);
            prices[count] = currentPrice;
            demands[count] = tick.currencyDemandQ96;
            count++;
            currentPrice = tick.next;
        }

        // Phase 2: Iterate from highest to lowest, accumulating cumulativeDemandAboveQ96
        result = new TickAvailability[](count);
        uint256 cumulativeDemandAbove;

        for (uint256 i = count; i > 0;) {
            unchecked {
                i--;
            }
            result[i] = TickAvailability({
                price: prices[i],
                currencyDemandQ96: demands[i],
                cumulativeDemandAboveQ96: cumulativeDemandAbove,
                tokensAvailable: _computeTokensAvailable(totalSupply, cumulativeDemandAbove, prices[i])
            });
            cumulativeDemandAbove += demands[i];
        }
    }

    /// @notice Computes the token availability at every tick spacing interval (including uninitialized ticks)
    /// @param auction The auction to query
    /// @param fromPrice Starting price (snapped down to nearest tick boundary, must be >= floor)
    /// @param limit Maximum number of results to return (capped to MAX_RESULT)
    /// @return result An array of TickAvailability structs, ordered from lowest to highest price
    /// @return nextPrice The price to pass as fromPrice for the next page, or 0 if done
    function getTickAvailabilityFull(IContinuousClearingAuction auction, uint256 fromPrice, uint256 limit)
        external
        view
        returns (TickAvailability[] memory result, uint256 nextPrice)
    {
        uint256 floor = auction.floorPrice();
        uint256 tickSpacing = auction.tickSpacing();

        // Cap limit
        if (limit > MAX_RESULT) limit = MAX_RESULT;
        if (limit == 0) return (new TickAvailability[](0), 0);

        // Snap fromPrice down to nearest tick boundary and clamp to floor
        if (fromPrice < floor) {
            fromPrice = floor;
        } else {
            fromPrice -= (fromPrice - floor) % tickSpacing;
        }

        // Phase 1: Walk initialized tick linked list into struct
        InitTickData memory d;
        {
            uint256 cp = floor;
            while (cp != MAX_TICK_PTR && d.count < MAX_TICKS) {
                Tick memory tick = auction.ticks(cp);
                d.prices[d.count] = cp;
                d.demands[d.count] = tick.currencyDemandQ96;
                d.count++;
                cp = tick.next;
            }
        }

        if (d.count == 0) return (new TickAvailability[](0), 0);

        // Phase 2: Compute cumulativeAbove from highest to lowest
        {
            uint256 cumAbove;
            for (uint256 i = d.count; i > 0;) {
                unchecked { i--; }
                d.cumulativeAbove[i] = cumAbove;
                cumAbove += d.demands[i];
            }
        }

        // Phase 3: Enumerate
        return _enumerateFullTicks(auction.totalSupply(), tickSpacing, fromPrice, limit, d);
    }

    function _enumerateFullTicks(
        uint128 totalSupply,
        uint256 tickSpacing,
        uint256 fromPrice,
        uint256 limit,
        InitTickData memory d
    ) internal pure returns (TickAvailability[] memory result, uint256 nextPrice) {
        uint256 highestInitPrice = d.prices[d.count - 1];
        if (fromPrice > highestInitPrice) return (new TickAvailability[](0), 0);

        // Find starting initialized tick index
        uint256 initIdx;
        while (initIdx + 1 < d.count && d.prices[initIdx + 1] <= fromPrice) {
            initIdx++;
        }

        // Compute result count
        uint256 maxTicks = ((highestInitPrice - fromPrice) / tickSpacing) + 1;
        if (maxTicks > limit) maxTicks = limit;

        result = new TickAvailability[](maxTicks);
        uint256 price = fromPrice;

        for (uint256 i; i < maxTicks; i++) {
            while (initIdx + 1 < d.count && d.prices[initIdx + 1] <= price) {
                initIdx++;
            }

            uint256 cumDemandAbove = d.cumulativeAbove[initIdx];
            result[i] = TickAvailability({
                price: price,
                currencyDemandQ96: (d.prices[initIdx] == price) ? d.demands[initIdx] : 0,
                cumulativeDemandAboveQ96: cumDemandAbove,
                tokensAvailable: _computeTokensAvailable(totalSupply, cumDemandAbove, price)
            });

            price += tickSpacing;
        }

        if (price <= highestInitPrice) {
            nextPrice = price;
        }
    }

    /// @notice Computes the tokens available at a tick given cumulative demand above it
    /// @dev tokensAvailable = totalSupply - cumulativeDemandAbove / price, clamped to 0
    /// @dev currencyDemandQ96 is stored as (bidAmount << 96) * MPS / mpsRemaining, i.e. Q96-scaled currency.
    ///      Dividing by priceQ96 (also Q96-scaled) yields raw token amount.
    function _computeTokensAvailable(uint128 totalSupply, uint256 cumulativeDemandAboveQ96, uint256 priceQ96)
        internal
        pure
        returns (uint256)
    {
        if (cumulativeDemandAboveQ96 == 0) return uint256(totalSupply);
        uint256 tokensConsumed = cumulativeDemandAboveQ96 / priceQ96;
        if (tokensConsumed >= totalSupply) return 0;
        return uint256(totalSupply) - tokensConsumed;
    }
}
