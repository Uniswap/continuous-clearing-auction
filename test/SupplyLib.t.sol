// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {SupplyLib, SupplyRolloverMultiplier} from '../src/libraries/SupplyLib.sol';

import {ValueX7, ValueX7Lib} from '../src/libraries/ValueX7Lib.sol';
import {ValueX7X7, ValueX7X7Lib} from '../src/libraries/ValueX7X7Lib.sol';

import {Assertions} from './utils/Assertions.sol';
import {MockSupplyLib} from './utils/MockSupplyLib.sol';
import {Test} from 'forge-std/Test.sol';

contract SupplyLibTest is Assertions, Test {
    using ValueX7Lib for *;
    using ValueX7X7Lib for *;

    MockSupplyLib mockSupplyLib;

    function setUp() public {
        mockSupplyLib = new MockSupplyLib();
    }

    /// @notice Test basic pack and unpack functionality with fuzzing
    function test_packUnpack_fuzz(bool set, uint24 remainingMps, ValueX7X7 remainingCurrencyRaisedX7X7) public view {
        // Bound the supply value to fit in 231 bits
        vm.assume(
            ValueX7X7.unwrap(remainingCurrencyRaisedX7X7)
                <= ValueX7X7.unwrap(SupplyLib.MAX_REMAINING_CURRENCY_RAISED_X7_X7)
        );

        // Pack the values
        SupplyRolloverMultiplier packed =
            mockSupplyLib.packSupplyRolloverMultiplier(set, remainingMps, remainingCurrencyRaisedX7X7);

        // Unpack and verify
        (bool unpackedSet, uint24 unpackedMps, ValueX7X7 unpackedCurrencyRaisedX7X7) = mockSupplyLib.unpack(packed);

        assertEq(unpackedSet, set, 'Set flag mismatch');
        assertEq(unpackedMps, remainingMps, 'Remaining MPS mismatch');
        assertEq(unpackedCurrencyRaisedX7X7, remainingCurrencyRaisedX7X7);
    }

    /// @notice Test packing with maximum values for each field
    function test_packUnpack_maxValues() public view {
        // Test with max values that fit in their respective bit ranges
        bool set = true;
        uint24 remainingMps = type(uint24).max;
        ValueX7X7 remainingCurrencyRaisedX7X7 = SupplyLib.MAX_REMAINING_CURRENCY_RAISED_X7_X7;

        SupplyRolloverMultiplier packed =
            mockSupplyLib.packSupplyRolloverMultiplier(set, remainingMps, remainingCurrencyRaisedX7X7);
        (bool unpackedSet, uint24 unpackedMps, ValueX7X7 unpackedCurrencyRaisedX7X7) = mockSupplyLib.unpack(packed);

        assertEq(unpackedSet, set);
        assertEq(unpackedMps, remainingMps);
        assertEq(unpackedCurrencyRaisedX7X7, remainingCurrencyRaisedX7X7);
    }

    /// @notice Test packing with minimum values for each field
    function test_packUnpack_minValues() public view {
        bool set = false;
        uint24 remainingMps = 0;
        ValueX7X7 remainingCurrencyRaisedX7X7 = ValueX7X7.wrap(0);

        SupplyRolloverMultiplier packed =
            mockSupplyLib.packSupplyRolloverMultiplier(set, remainingMps, remainingCurrencyRaisedX7X7);
        (bool unpackedSet, uint24 unpackedMps, ValueX7X7 unpackedCurrencyRaisedX7X7) = mockSupplyLib.unpack(packed);

        assertEq(unpackedSet, set);
        assertEq(unpackedMps, remainingMps);
        assertEq(unpackedCurrencyRaisedX7X7, remainingCurrencyRaisedX7X7);

        // When all values are zero/false, the raw value should be 0
        assertEq(SupplyRolloverMultiplier.unwrap(packed), 0);
    }

    /// @notice Test edge case: supply value exactly at the 231-bit boundary
    function test_packUnpack_fuzz_remainingSupplyIsMax(bool set, uint24 remainingMps) public view {
        ValueX7X7 remainingCurrencyRaisedX7X7 = SupplyLib.MAX_REMAINING_CURRENCY_RAISED_X7_X7;

        SupplyRolloverMultiplier packed =
            mockSupplyLib.packSupplyRolloverMultiplier(set, remainingMps, remainingCurrencyRaisedX7X7);
        (bool unpackedSet, uint24 unpackedMps, ValueX7X7 unpackedCurrencyRaisedX7X7) = mockSupplyLib.unpack(packed);

        assertEq(unpackedSet, set);
        assertEq(unpackedMps, remainingMps);
        assertEq(unpackedCurrencyRaisedX7X7, SupplyLib.MAX_REMAINING_CURRENCY_RAISED_X7_X7);
    }

    /// @notice Fuzz test for toX7X7 function
    function testFuzz_toX7X7(uint128 totalSupply) public view {
        ValueX7X7 result = mockSupplyLib.toX7X7(totalSupply);

        // The result should be totalSupply * 1e7 * 1e7
        assertEq(ValueX7X7.unwrap(result), totalSupply * ValueX7Lib.X7 ** 2);
    }

    function testFuzz_remainingSupplyDoesNotOverflow(uint24 mps, uint256 currencyRaised1, uint256 currencyRaised2)
        public
        view
    {
        currencyRaised1 = _bound(currencyRaised1, 0, ValueX7X7.unwrap(SupplyLib.MAX_REMAINING_CURRENCY_RAISED_X7_X7));
        currencyRaised2 = _bound(currencyRaised2, 0, ValueX7X7.unwrap(SupplyLib.MAX_REMAINING_CURRENCY_RAISED_X7_X7));
        vm.assume(currencyRaised1 < currencyRaised2);

        // Pack with same set flag and mps, different supplies
        SupplyRolloverMultiplier packed1 =
            mockSupplyLib.packSupplyRolloverMultiplier(false, mps, ValueX7X7.wrap(currencyRaised1));

        SupplyRolloverMultiplier packed2 =
            mockSupplyLib.packSupplyRolloverMultiplier(false, mps, ValueX7X7.wrap(currencyRaised2));

        (,, ValueX7X7 currencyRaised1X7X7) = mockSupplyLib.unpack(packed1);
        (,, ValueX7X7 currencyRaised2X7X7) = mockSupplyLib.unpack(packed2);
        // Assert that the supply values are the same as the inputs
        assertEq(ValueX7X7.unwrap(currencyRaised1X7X7), currencyRaised1);
        assertEq(ValueX7X7.unwrap(currencyRaised2X7X7), currencyRaised2);
        // Assert that the inequality still holds - implying that mps has not been overridden
        assertTrue(ValueX7X7.unwrap(currencyRaised1X7X7) < ValueX7X7.unwrap(currencyRaised2X7X7));
    }
}
