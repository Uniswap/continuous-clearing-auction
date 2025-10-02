// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Auction} from '../../src/Auction.sol';
import {AuctionParameters} from '../../src/Auction.sol';

import {ConstantsLib} from '../../src/libraries/ConstantsLib.sol';
import {DemandLib} from '../../src/libraries/DemandLib.sol';
import {FixedPoint96} from '../../src/libraries/FixedPoint96.sol';
import {ValueX7, ValueX7Lib} from '../../src/libraries/ValueX7Lib.sol';
import {ValueX7X7, ValueX7X7Lib} from '../../src/libraries/ValueX7X7Lib.sol';
import {FuzzDeploymentParams} from '../utils/FuzzStructs.sol';
import {AuctionUnitTest} from './AuctionUnitTest.sol';
import {FixedPointMathLib} from 'solady/utils/FixedPointMathLib.sol';

contract AuctionCalculateClearingPriceTest is AuctionUnitTest {
    using ValueX7Lib for *;
    using ValueX7X7Lib for *;
    using DemandLib for ValueX7;
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

    function testFuzz_calculateClearingPrice(
        FuzzDeploymentParams memory _deploymentParams,
        ValueX7 sumCurrencyDemandAboveClearingX7,
        uint256 remainingSupply,
        uint24 remainingMps
    ) public setUpMockAuctionFuzz(_deploymentParams) givenValidMps(remainingMps) {
        // bound both demand values to uint128 max which is reasonably large
        // this prevents overflow when multiplying by Q96
        sumCurrencyDemandAboveClearingX7 =
            ValueX7.wrap(_bound(ValueX7.unwrap(sumCurrencyDemandAboveClearingX7), 0, type(uint128).max));

        ValueX7X7 remainingSupplyX7X7 = ValueX7X7.wrap(remainingSupply);

        vm.assume(ValueX7X7.unwrap(remainingSupplyX7X7) > 0);

        uint256 clearingPrice =
            mockAuction.calculateNewClearingPrice(sumCurrencyDemandAboveClearingX7, remainingSupplyX7X7, remainingMps);

        // Price without rounding to tick spacing
        uint256 unroundedPrice =
            _calculateUnroundedPrice(sumCurrencyDemandAboveClearingX7, remainingSupplyX7X7, remainingMps);

        // Clearing price must always be greater than or equal to unrounded price
        assertGe(clearingPrice, unroundedPrice);

        uint256 tickSpacing = mockAuction.tickSpacing();
        if (unroundedPrice % tickSpacing != 0) {
            // If the price is not aligned to a tick spacing, clearing price must be greater than unrounded price
            assertGt(clearingPrice, unroundedPrice);
            // Clearing price must be aligned to tick spacing
            assertEq(clearingPrice % tickSpacing, 0);
            // Clearing price must be rounded up to the next tick spacing
            assertEq(clearingPrice, helper__roundPriceUpToTickSpacing(unroundedPrice, tickSpacing));
        } else {
            // Else, prices must be equal
            assertEq(clearingPrice, unroundedPrice);
        }
    }
}
