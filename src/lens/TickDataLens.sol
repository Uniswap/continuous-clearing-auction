// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {TickStorage} from '../TickStorage.sol';
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

    /// @notice The maximum number of initialized ticks which can be returned
    uint256 public constant MAX_BUFFER_SIZE = 1000;

    /// @notice Function to be called from offchain to get the data of all initialized ticks above a given price
    /// @dev A maximum of `MAX_BUFFER_SIZE` ticks above the current clearing price will be returned
    ///      Returned values may be stale if the auction has not been recently checkpointed
    function getInitializedTickData(IContinuousClearingAuction auction)
        public
        view
        returns (TickWithData[] memory ticks)
    {
        uint256 totalSupply = auction.totalSupply();
        uint24 remainingMps = ConstantsLib.MPS - auction.latestCheckpoint().cumulativeMps;
        uint256 price = auction.nextActiveTickPrice();

        Tick memory t = auction.ticks(price);

        uint256 sumCurrencyDemandAboveClearingQ96 = auction.sumCurrencyDemandAboveClearingQ96();
        uint256 next = price;
        uint256 idx;

        uint256 fmp;
        // Save the current free memory pointer
        assembly {
            fmp := mload(0x40)
        }

        while (idx < MAX_BUFFER_SIZE) {
            uint256 requiredCurrencyDemandQ96 = totalSupply * next;
            uint256 currencyDemandQ96 = t.currencyDemandQ96;
            uint256 nextTick = t.next;
            uint256 currencyRequiredQ96 = requiredCurrencyDemandQ96.saturatingSub(sumCurrencyDemandAboveClearingQ96)
                .fullMulDivUp(remainingMps, ConstantsLib.MPS);

            // Write the TickWithData struct fields (4 x 32 bytes = 0x80) directly to fmp + idx * 0x80,
            // then advance the free memory pointer to protect this data from subsequent allocations
            assembly {
                let offset := add(fmp, mul(idx, 0x80))
                mstore(offset, next)
                mstore(add(offset, 0x20), currencyDemandQ96)
                mstore(add(offset, 0x40), requiredCurrencyDemandQ96)
                mstore(add(offset, 0x60), currencyRequiredQ96)
                mstore(0x40, add(offset, 0x80))
            }

            sumCurrencyDemandAboveClearingQ96 -= currencyDemandQ96;
            unchecked {
                ++idx;
            }
            next = nextTick;
            if (next == type(uint256).max) break;
            t = auction.ticks(next);
        }

        // Assemble the Solidity memory layout for a TickWithData[] return value:
        //   [length][ptr_0..ptr_{n-1}][struct_0..struct_{n-1}]
        assembly {
            let headerSize := add(0x20, shl(5, idx)) // 32 + idx * 32
            let dataSize := shl(7, idx) // idx * 128
            mcopy(add(fmp, headerSize), fmp, dataSize)
            ticks := fmp
            mstore(ticks, idx)
            let dataOffset := add(fmp, headerSize)
            for { let i := 0 } lt(i, idx) { i := add(i, 1) } {
                mstore(add(add(ticks, 0x20), shl(5, i)), add(dataOffset, mul(i, 0x80)))
            }
            mstore(0x40, add(dataOffset, dataSize))
        }
    }
}
