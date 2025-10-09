// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import {BttBase} from 'btt/BttBase.sol';
import {SupplyLib, SupplyRolloverMultiplier, ValueX7X7} from 'twap-auction/libraries/SupplyLib.sol';

contract PackSupplyRolloverMultiplierRef {
    function packSupplyRolloverMultiplier(bool set, uint24 remainingMps, ValueX7X7 remainingCurrencyRaisedX7X7)
        external
        pure
        returns (SupplyRolloverMultiplier)
    {
        return SupplyLib.packSupplyRolloverMultiplier(set, remainingMps, remainingCurrencyRaisedX7X7);
    }
}

contract PackSupplyRolloverMultiplierTest is BttBase {
    function test_WhenRemainingCurrencyRaisedX7X7GT231Bits(
        bool _set,
        uint24 _remainingMps,
        ValueX7X7 _remainingCurrencyRaisedX7X7
    ) external {
        ValueX7X7 remainingCurrencyRaisedX7X7 =
            ValueX7X7.wrap(bound(ValueX7X7.unwrap(_remainingCurrencyRaisedX7X7), (1 << 231), type(uint256).max));
        // it will revert

        PackSupplyRolloverMultiplierRef packSupplyRolloverMultiplierRef = new PackSupplyRolloverMultiplierRef();

        vm.expectRevert();
        packSupplyRolloverMultiplierRef.packSupplyRolloverMultiplier(_set, _remainingMps, remainingCurrencyRaisedX7X7);
    }

    function test_WhenRemainingCurrencyRaisedX7X7LE231Bits(
        bool _set,
        uint24 _remainingMps,
        ValueX7X7 _remainingCurrencyRaisedX7X7
    ) external {
        // it will unpack to the same values
        ValueX7X7 remainingCurrencyRaisedX7X7 =
            ValueX7X7.wrap(bound(ValueX7X7.unwrap(_remainingCurrencyRaisedX7X7), 0, (1 << 231) - 1));

        SupplyRolloverMultiplier packed =
            SupplyLib.packSupplyRolloverMultiplier(_set, _remainingMps, remainingCurrencyRaisedX7X7);

        (bool unpackedSet, uint24 unpackedMps, ValueX7X7 unpackedCurrencyRaisedX7X7) = SupplyLib.unpack(packed);

        assertEq(unpackedSet, _set, 'isSet');
        assertEq(unpackedMps, _remainingMps, 'remainingMps');
        assertEq(unpackedCurrencyRaisedX7X7, remainingCurrencyRaisedX7X7, 'remainingCurrencyRaisedX7X7');
    }
}
