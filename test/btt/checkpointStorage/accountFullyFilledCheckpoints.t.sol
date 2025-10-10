// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import {BttBase} from 'btt/BttBase.sol';
import {MockCheckpointStorage} from 'btt/mocks/MockCheckpointStorage.sol';

import {FixedPointMathLib} from 'solady/utils/FixedPointMathLib.sol';
import {Bid} from 'twap-auction/libraries/BidLib.sol';
import {Checkpoint} from 'twap-auction/libraries/CheckpointLib.sol';
import {ConstantsLib} from 'twap-auction/libraries/ConstantsLib.sol';
import {FixedPoint96} from 'twap-auction/libraries/FixedPoint96.sol';

contract AccountFullyFilledCheckpointsTest is BttBase {
    MockCheckpointStorage public mockCheckpointStorage;

    function setUp() external {
        mockCheckpointStorage = new MockCheckpointStorage();
    }

    function test_WhenCalledWithParams(Bid memory _bid, Checkpoint memory _upper, Checkpoint memory _startCheckpoint)
        external
    {
        // it will compute deltas
        // it will call calculateFill with those deltas
        // it will return the tokens filled
        // it will return the currency spent

        _bid.startCumulativeMps = uint24(bound(_bid.startCumulativeMps, 0, ConstantsLib.MPS - 1));
        _bid.amount = bound(_bid.amount, 1, type(uint128).max);

        _startCheckpoint.cumulativeMpsPerPrice = bound(_startCheckpoint.cumulativeMpsPerPrice, 0, type(uint128).max - 1);
        _startCheckpoint.cumulativeMps = uint24(bound(_startCheckpoint.cumulativeMps, 0, ConstantsLib.MPS - 2));

        _upper.cumulativeMpsPerPrice =
            bound(_upper.cumulativeMpsPerPrice, _startCheckpoint.cumulativeMpsPerPrice + 1, type(uint128).max);
        _upper.cumulativeMps =
            uint24(bound(_upper.cumulativeMps, _startCheckpoint.cumulativeMps + 1, ConstantsLib.MPS - 1));

        (uint256 tokensFilled, uint256 currencySpent) =
            mockCheckpointStorage.accountFullyFilledCheckpoints(_upper, _startCheckpoint, _bid);

        uint256 left = ConstantsLib.MPS - _bid.startCumulativeMps;
        uint256 cumulativeMpsPerPriceDelta = _upper.cumulativeMpsPerPrice - _startCheckpoint.cumulativeMpsPerPrice;
        uint256 cumulativeMpsDelta = _upper.cumulativeMps - _startCheckpoint.cumulativeMps;

        // Simple maths in uint256. Allow 1 wei diff
        assertApproxEqAbs(
            tokensFilled, _bid.amount * cumulativeMpsPerPriceDelta / (FixedPoint96.Q96 * left), 1, 'tokens filled'
        );
        assertApproxEqAbs(currencySpent, _bid.amount * cumulativeMpsDelta / left, 1, 'currency spent');

        // Intermediate 512 bits.
        assertEq(
            tokensFilled,
            FixedPointMathLib.fullMulDiv(_bid.amount, cumulativeMpsPerPriceDelta, FixedPoint96.Q96 * left),
            'tokens filled'
        );
        assertEq(currencySpent, FixedPointMathLib.fullMulDivUp(_bid.amount, cumulativeMpsDelta, left), 'currency spent');
    }
}
