// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import {BttBase} from 'btt/BttBase.sol';
import {SupplyLib, ValueX7X7} from 'twap-auction/libraries/SupplyLib.sol';

contract ToX7X7Ref {
    function toX7X7(uint256 totalSupply) external pure returns (ValueX7X7) {
        return SupplyLib.toX7X7(totalSupply);
    }
}

contract ToX7X7Test is BttBase {
    function test_WhenTotalSupplyGTUint256MaxDiv1e14(uint256 _totalSupply) external {
        // it reverts with {MathOverflow}

        uint256 totalSupply = bound(_totalSupply, type(uint256).max / 1e14 + 1, type(uint256).max);

        ToX7X7Ref toX7X7Ref = new ToX7X7Ref();
        vm.expectRevert();
        toX7X7Ref.toX7X7(totalSupply);
    }

    function test_WhenTotalSupplyLEUint256MaxDiv1e14(uint256 _totalSupply) external {
        // it returns totalSupply * 1e7 * 1e7

        uint256 totalSupply = bound(_totalSupply, 0, type(uint256).max / 1e14);
        ValueX7X7 result = SupplyLib.toX7X7(totalSupply);
        assertEq(ValueX7X7.unwrap(result), totalSupply * 1e14);
    }
}
