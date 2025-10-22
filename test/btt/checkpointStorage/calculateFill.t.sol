// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import {BttBase} from 'btt/BttBase.sol';
import {MockCheckpointStorage} from 'btt/mocks/MockCheckpointStorage.sol';

import {FixedPointMathLib} from 'solady/utils/FixedPointMathLib.sol';
import {Bid} from 'twap-auction/libraries/BidLib.sol';
import {ConstantsLib} from 'twap-auction/libraries/ConstantsLib.sol';
import {FixedPoint96} from 'twap-auction/libraries/FixedPoint96.sol';

contract CalculateFillTest is BttBase {
    MockCheckpointStorage public mockCheckpointStorage;

    function setUp() external {
        mockCheckpointStorage = new MockCheckpointStorage();
    }

    function test_WhenCalledWithParams(
        Bid memory _bid,
        uint256 _cumulativeMpsPerPriceDelta,
        uint24 _cumulativeMpsDelta
    ) external view {
        // it returns the tokens filled
        // it returns the currency spent

        // Must ensure that `startCumulativeMps != MPS` as it would div with 0.

        _bid.startCumulativeMps = uint24(bound(_bid.startCumulativeMps, 0, ConstantsLib.MPS - 1));
        _bid.amountQ96 = bound(_bid.amountQ96, 1, type(uint128).max);

        uint256 left = ConstantsLib.MPS - _bid.startCumulativeMps;

        _cumulativeMpsPerPriceDelta = bound(_cumulativeMpsPerPriceDelta, 1, type(uint128).max);

        (uint256 tokensFilled, uint256 currencySpent) =
            mockCheckpointStorage.calculateFill(_bid, _cumulativeMpsPerPriceDelta, _cumulativeMpsDelta);

        uint256 q96Sqr = FixedPoint96.Q96 * FixedPoint96.Q96;

        // Simple maths in uint256. Allow 1 wei diff
        assertApproxEqAbs(
            tokensFilled, _bid.amountQ96 * _cumulativeMpsPerPriceDelta / (q96Sqr * left), 1, 'tokens filled'
        );
        assertApproxEqAbs(currencySpent, _bid.amountQ96 * _cumulativeMpsDelta / left, 1, 'currency spent');

        // Intermediate 512 bits.
        assertEq(
            tokensFilled,
            FixedPointMathLib.fullMulDiv(_bid.amountQ96, _cumulativeMpsPerPriceDelta, q96Sqr * left),
            'tokens filled'
        );
        assertEq(
            currencySpent, FixedPointMathLib.fullMulDivUp(_bid.amountQ96, _cumulativeMpsDelta, left), 'currency spent'
        );
    }
}
