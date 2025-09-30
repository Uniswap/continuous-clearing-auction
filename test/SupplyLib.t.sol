// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {SupplyLib, SupplyRolloverMultiplier} from '../src/libraries/SupplyLib.sol';

import {ValueX7, ValueX7Lib} from '../src/libraries/ValueX7Lib.sol';
import {ValueX7X7, ValueX7X7Lib} from '../src/libraries/ValueX7X7Lib.sol';
import {MockSupplyLib} from './utils/MockSupplyLib.sol';
import {Test} from 'forge-std/Test.sol';

contract SupplyLibTest is Test {
    using ValueX7Lib for *;
    using ValueX7X7Lib for *;

    MockSupplyLib mockSupplyLib;

    function setUp() public {
        mockSupplyLib = new MockSupplyLib();
    }

    /// @notice Test basic pack and unpack functionality with fuzzing
    function test_packUnpack_fuzz(bool set, uint24 remainingMps, uint256 remainingSupplyRaw) public view {
        // Bound the supply value to fit in 231 bits
        vm.assume(remainingSupplyRaw <= SupplyLib.MAX_REMAINING_SUPPLY);
        ValueX7X7 remainingSupplyX7X7 = ValueX7X7.wrap(remainingSupplyRaw);

        // Pack the values
        SupplyRolloverMultiplier packed =
            mockSupplyLib.packSupplyRolloverMultiplier(set, remainingMps, remainingSupplyX7X7);

        // Unpack and verify
        (bool unpackedSet, uint24 unpackedMps, ValueX7X7 unpackedSupply) = mockSupplyLib.unpack(packed);

        assertEq(unpackedSet, set, 'Set flag mismatch');
        assertEq(unpackedMps, remainingMps, 'Remaining MPS mismatch');
        assertEq(ValueX7X7.unwrap(unpackedSupply), ValueX7X7.unwrap(remainingSupplyX7X7), 'Supply value mismatch');
    }

    /// @notice Test packing with maximum values for each field
    function test_packUnpack_maxValues() public view {
        // Test with max values that fit in their respective bit ranges
        bool set = true;
        uint24 remainingMps = type(uint24).max;
        ValueX7X7 remainingSupplyX7X7 = ValueX7X7.wrap(SupplyLib.MAX_REMAINING_SUPPLY);

        SupplyRolloverMultiplier packed =
            mockSupplyLib.packSupplyRolloverMultiplier(set, remainingMps, remainingSupplyX7X7);
        (bool unpackedSet, uint24 unpackedMps, ValueX7X7 unpackedSupply) = mockSupplyLib.unpack(packed);

        assertEq(unpackedSet, set);
        assertEq(unpackedMps, remainingMps);
        assertEq(ValueX7X7.unwrap(unpackedSupply), ValueX7X7.unwrap(remainingSupplyX7X7));
    }

    /// @notice Test packing with minimum values for each field
    function test_packUnpack_minValues() public view {
        bool set = false;
        uint24 remainingMps = 0;
        ValueX7X7 remainingSupplyX7X7 = ValueX7X7.wrap(0);

        SupplyRolloverMultiplier packed =
            mockSupplyLib.packSupplyRolloverMultiplier(set, remainingMps, remainingSupplyX7X7);
        (bool unpackedSet, uint24 unpackedMps, ValueX7X7 unpackedSupply) = mockSupplyLib.unpack(packed);

        assertEq(unpackedSet, set);
        assertEq(unpackedMps, remainingMps);
        assertEq(ValueX7X7.unwrap(unpackedSupply), ValueX7X7.unwrap(remainingSupplyX7X7));

        // When all values are zero/false, the raw value should be 0
        assertEq(SupplyRolloverMultiplier.unwrap(packed), 0);
    }

    /// @notice Test edge case: supply value exactly at the 231-bit boundary
    function test_packUnpack_fuzz_remainingSupplyIsMax(bool set, uint24 remainingMps) public view {
        ValueX7X7 remainingSupplyX7X7 = ValueX7X7.wrap(SupplyLib.MAX_REMAINING_SUPPLY);

        SupplyRolloverMultiplier packed =
            mockSupplyLib.packSupplyRolloverMultiplier(set, remainingMps, remainingSupplyX7X7);
        (bool unpackedSet, uint24 unpackedMps, ValueX7X7 unpackedSupply) = mockSupplyLib.unpack(packed);

        assertEq(unpackedSet, set);
        assertEq(unpackedMps, remainingMps);
        assertEq(ValueX7X7.unwrap(unpackedSupply), SupplyLib.MAX_REMAINING_SUPPLY);
    }

    /// @notice Test that bit fields don't interfere with each other
    function test_bitFieldIsolation() public view {
        // Max supply, other fields zero
        SupplyRolloverMultiplier packed1 =
            mockSupplyLib.packSupplyRolloverMultiplier(false, 0, ValueX7X7.wrap(SupplyLib.MAX_REMAINING_SUPPLY));
        (bool set1, uint24 mps1, ValueX7X7 supply1) = mockSupplyLib.unpack(packed1);
        assertEq(set1, false);
        assertEq(mps1, 0);
        assertEq(ValueX7X7.unwrap(supply1), SupplyLib.MAX_REMAINING_SUPPLY);

        // Max MPS, other fields zero
        SupplyRolloverMultiplier packed2 =
            mockSupplyLib.packSupplyRolloverMultiplier(false, type(uint24).max, ValueX7X7.wrap(0));
        (bool set2, uint24 mps2, ValueX7X7 supply2) = mockSupplyLib.unpack(packed2);
        assertEq(set2, false);
        assertEq(mps2, type(uint24).max);
        assertEq(ValueX7X7.unwrap(supply2), 0);

        // Only set flag true, other fields zero
        SupplyRolloverMultiplier packed3 = mockSupplyLib.packSupplyRolloverMultiplier(true, 0, ValueX7X7.wrap(0));
        (bool set3, uint24 mps3, ValueX7X7 supply3) = mockSupplyLib.unpack(packed3);
        assertEq(set3, true);
        assertEq(mps3, 0);
        assertEq(ValueX7X7.unwrap(supply3), 0);
    }

    /// @notice Fuzz test for toX7X7 function
    function testFuzz_toX7X7(uint256 totalSupply) public view {
        // Bound to MAX_TOTAL_SUPPLY to avoid overflow
        totalSupply = _bound(totalSupply, 0, SupplyLib.MAX_TOTAL_SUPPLY);

        ValueX7X7 result = mockSupplyLib.toX7X7(totalSupply);

        // The result should be totalSupply * 1e7 * 1e7
        assertEq(ValueX7X7.unwrap(result), totalSupply * ValueX7Lib.X7 ** 2);
    }

    /// @notice Test toX7X7 with boundary values
    function test_toX7X7_boundaries() public view {
        // Test with 0
        assertEq(ValueX7X7.unwrap(mockSupplyLib.toX7X7(0)), 0);

        // Test with MAX_TOTAL_SUPPLY
        ValueX7X7 maxResult = mockSupplyLib.toX7X7(SupplyLib.MAX_TOTAL_SUPPLY);
        assertEq(ValueX7X7.unwrap(maxResult), SupplyLib.MAX_TOTAL_SUPPLY * ValueX7Lib.X7 ** 2);
    }

    /// @notice Test specific bit patterns to ensure correct masking
    function test_specificBitPatterns() public view {
        // Test alternating bit patterns
        uint24 mpsPattern = 0xAAAAAA; // Alternating 1s and 0s in 24 bits
        ValueX7X7 supplyPattern = ValueX7X7.wrap(0x5555555555555555555555555555555); // Alternating pattern

        SupplyRolloverMultiplier packed = mockSupplyLib.packSupplyRolloverMultiplier(true, mpsPattern, supplyPattern);

        (bool unpackedSet, uint24 unpackedMps, ValueX7X7 unpackedSupply) = mockSupplyLib.unpack(packed);

        assertEq(unpackedSet, true);
        assertEq(unpackedMps, mpsPattern);
        assertEq(ValueX7X7.unwrap(unpackedSupply), ValueX7X7.unwrap(supplyPattern));
    }

    function testFuzz_remainingSupplyDoesNotOverflow(uint24 mps, uint256 supply1, uint256 supply2) public view {
        vm.assume(supply1 <= SupplyLib.MAX_REMAINING_SUPPLY);
        vm.assume(supply2 <= SupplyLib.MAX_REMAINING_SUPPLY);
        vm.assume(supply1 < supply2);

        // Pack with same set flag and mps, different supplies
        SupplyRolloverMultiplier packed1 =
            mockSupplyLib.packSupplyRolloverMultiplier(false, mps, ValueX7X7.wrap(supply1));

        SupplyRolloverMultiplier packed2 =
            mockSupplyLib.packSupplyRolloverMultiplier(false, mps, ValueX7X7.wrap(supply2));

        (,, ValueX7X7 supply1X7X7) = mockSupplyLib.unpack(packed1);
        (,, ValueX7X7 supply2X7X7) = mockSupplyLib.unpack(packed2);
        // Assert that the supply values are the same as the inputs
        assertEq(ValueX7X7.unwrap(supply1X7X7), supply1);
        assertEq(ValueX7X7.unwrap(supply2X7X7), supply2);
        // Assert that the inequality still holds - implying that mps has not been overridden
        assertTrue(ValueX7X7.unwrap(supply1X7X7) < ValueX7X7.unwrap(supply2X7X7));
    }
}
