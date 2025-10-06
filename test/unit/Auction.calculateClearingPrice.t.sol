// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Auction} from '../../src/Auction.sol';
import {AuctionParameters} from '../../src/Auction.sol';
import {ConstantsLib} from '../../src/libraries/ConstantsLib.sol';
import {FixedPoint96} from '../../src/libraries/FixedPoint96.sol';
import {ValueX7, ValueX7Lib} from '../../src/libraries/ValueX7Lib.sol';
import {ValueX7X7, ValueX7X7Lib} from '../../src/libraries/ValueX7X7Lib.sol';
import {FuzzDeploymentParams} from '../utils/FuzzStructs.sol';
import {AuctionUnitTest} from './AuctionUnitTest.sol';
import {FixedPointMathLib} from 'solady/utils/FixedPointMathLib.sol';

contract AuctionCalculateClearingPriceTest is AuctionUnitTest {
    using ValueX7Lib for *;
    using ValueX7X7Lib for *;
    using FixedPointMathLib for uint256;

    /// @notice Helper function to calculate clearing price without tick spacing rounding
    /// @dev This replicates the core calculation from _calculateNewClearingPrice but without the final tick alignment
    function _calculateUnroundedPrice(
        ValueX7 sumCurrencyDemandAboveClearingX7,
        ValueX7X7 remainingSupplyX7X7,
        uint24 remainingMps
    ) internal pure returns (uint256) {
        return ValueX7.unwrap(
            sumCurrencyDemandAboveClearingX7.fullMulDivUp(
                ValueX7.wrap(FixedPoint96.Q96 * uint256(remainingMps)), remainingSupplyX7X7.downcast()
            )
        );
    }

    modifier givenValidMps(uint24 remainingMps) {
        vm.assume(remainingMps > 0 && remainingMps <= ConstantsLib.MPS);
        _;
    }
}
