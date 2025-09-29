// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {SupplyLib, SupplyRolloverMultiplier} from '../../src/libraries/SupplyLib.sol';
import {ValueX7X7} from '../../src/libraries/ValueX7X7Lib.sol';

/// @notice Mock implementation of the SupplyLib for testing
contract MockSupplyLib {
    /// @notice Pack values into a SupplyRolloverMultiplier
    function packSupplyRolloverMultiplier(bool set, uint24 remainingMps, ValueX7X7 remainingSupplyX7X7)
        external
        pure
        returns (SupplyRolloverMultiplier)
    {
        return SupplyLib.packSupplyRolloverMultiplier(set, remainingMps, remainingSupplyX7X7);
    }

    /// @notice Unpack a SupplyRolloverMultiplier into its components
    function unpack(SupplyRolloverMultiplier multiplier)
        external
        pure
        returns (bool isSet, uint24 remainingMps, ValueX7X7 remainingSupplyX7X7)
    {
        return SupplyLib.unpack(multiplier);
    }

    /// @notice Convert uint256 to ValueX7X7
    function toX7X7(uint256 totalSupply) external pure returns (ValueX7X7) {
        return SupplyLib.toX7X7(totalSupply);
    }
}
