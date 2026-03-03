// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IContinuousClearingAuction} from '../interfaces/IContinuousClearingAuction.sol';
import {Tick} from '../interfaces/ITickStorage.sol';
import {ConstantsLib} from '../libraries/ConstantsLib.sol';
import {AuctionState} from './AuctionStateLens.sol';
import {FixedPointMathLib} from 'solady/utils/FixedPointMathLib.sol';

/// @notice Tick data with additional computed values
/// @dev Use the ratio between `sumCurrencyDemandAboveClearingQ96` in the auction
///      and `requiredCurrencyDemandQ96` to calculate the progress towards the tick
///      Use `currencyRequiredQ96` to calculate the additional currency needed to move the clearing price to the tick.
struct TickWithData {
    uint256 priceQ96; // the price of the tick
    uint256 currencyDemandQ96; // the current demand at the tick
    uint256 requiredCurrencyDemandQ96; // the required demand to move the clearing price to the tick
    uint256 currencyRequiredQ96; // the additional currency required to move the clearing price to the tick
}

/// @title TickDataLens
/// @notice Contract for reading data from initialized ticks of an auction
contract TickDataLens {
    using FixedPointMathLib for *;

    /// @notice The maximum number of initialized ticks to return
    uint256 internal constant MAX_BUFFER_SIZE = 1000;

    /// @notice Function to be called from offchain to get the data of all initialized ticks above a given price
    /// @dev A maximum of `MAX_BUFFER_SIZE` ticks above the current clearing price will be returned
    function getInitializedTickData(IContinuousClearingAuction auction) public view returns (TickWithData[] memory) {
        TickWithData[] memory buffer = new TickWithData[](MAX_BUFFER_SIZE);
        uint256 idx = 0;

        // Block level constants
        uint256 totalSupply = auction.totalSupply();
        uint24 remainingMps = ConstantsLib.MPS - auction.latestCheckpoint().cumulativeMps;
        uint256 price = auction.nextActiveTickPrice();

        Tick memory t = auction.ticks(price);

        // Iteration variables
        uint256 sumCurrencyDemandAboveClearingQ96 = auction.sumCurrencyDemandAboveClearingQ96();
        uint256 next = price;

        while (t.next != 0 && idx < MAX_BUFFER_SIZE) {
            uint256 requiredCurrencyDemandQ96 = totalSupply * next;
            buffer[idx] = TickWithData({
                priceQ96: next,
                currencyDemandQ96: t.currencyDemandQ96,
                requiredCurrencyDemandQ96: requiredCurrencyDemandQ96,
                currencyRequiredQ96: requiredCurrencyDemandQ96.saturatingSub(sumCurrencyDemandAboveClearingQ96)
                    .fullMulDivUp(remainingMps, ConstantsLib.MPS)
            });
            // Subtract the demand at the current tick from the total demand
            sumCurrencyDemandAboveClearingQ96 -= t.currencyDemandQ96;
            idx++;
            next = t.next;
            // The last initialized tick points to the sentinel which is not a valid tick price
            if (next == type(uint256).max) break;
            t = auction.ticks(next);
        }
        // Truncate the buffer to the actual length
        assembly {
            mstore(buffer, idx)
        }
        return buffer;
    }
}
