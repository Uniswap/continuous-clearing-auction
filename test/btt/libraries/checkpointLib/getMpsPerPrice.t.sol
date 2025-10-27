// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import {BttBase} from 'btt/BttBase.sol';
import {CheckpointLib} from 'twap-auction/libraries/CheckpointLib.sol';

import {ConstantsLib} from 'twap-auction/libraries/ConstantsLib.sol';
import {FixedPoint96} from 'twap-auction/libraries/FixedPoint96.sol';

contract GetMpsPerPriceTest is BttBase {
    function test_WhenCalledWithPriceEQ0(uint24 _mps) external {
        // it returns 0

        assertEq(CheckpointLib.getMpsPerPrice(_mps, 0), 0);
    }

    function test_WhenCalledWithPriceGT0(uint24 _mpsPerBlock, uint256 _price) external {
        // it returns mpsPerBlock * Q96 ** 2 div price

        uint24 mpsPerBlock = uint24(bound(_mpsPerBlock, 0, ConstantsLib.MPS));
        uint256 price = bound(_price, 1, type(uint256).max);

        assertEq(CheckpointLib.getMpsPerPrice(mpsPerBlock, price), (mpsPerBlock * FixedPoint96.Q96 ** 2) / price);
    }
}
