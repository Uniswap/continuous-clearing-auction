// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ValueX7, ValueX7Lib} from './ValueX7Lib.sol';
import {ValueX7X7, ValueX7X7Lib} from './ValueX7X7Lib.sol';

/// @dev Custom type layout (256 bits total):
///      - Bit 255 (MSB): Boolean 'set' flag
///      - Bits 254-231 (24 bits): 'remainingMps' value
///      - Bits 230-0 (231 bits): 'remainingSupplyX7X7' value
type SupplyRolloverMultiplier is uint256;

/// @title SupplyLib
/// @notice Library for supply related functions
library SupplyLib {
    using ValueX7Lib for *;
    using ValueX7X7Lib for *;

    uint256 private constant REMAINING_MPS_BIT_POSITION = 231;
    uint256 private constant REMAINING_MPS_BIT_WIDTH = 24;

    // Masks with bit visualization:
    // SET_FLAG_MASK:        1000...0000 (bit 255 set)
    uint256 private constant SET_FLAG_MASK = 1 << 255;

    // REMAINING_MPS_MASK:
    //                       [255][254--------------------231][230-----------------------0]
    //                       [ 0 ][1111111111111111111111111][00000.....................00]
    uint256 private constant REMAINING_MPS_MASK = ((1 << REMAINING_MPS_BIT_WIDTH) - 1) << REMAINING_MPS_BIT_POSITION;

    // REMAINING_SUPPLY_MASK:
    //                        [255-231][230---------------------------------------------------------0]
    //                        [00...00][11111111111111111111111111111111111111111111111111...11111111]
    uint256 private constant REMAINING_SUPPLY_MASK = (1 << 231) - 1;

    // Max value for remainingSupplyX7X7 (231 bits set)
    uint256 public constant MAX_REMAINING_SUPPLY = REMAINING_SUPPLY_MASK;
    /// @notice The maximum total supply of tokens than can be sold in the auction
    uint256 public constant MAX_TOTAL_SUPPLY = MAX_REMAINING_SUPPLY / ValueX7Lib.X7 ** 2;

    /// @notice Convert the total supply to a ValueX7X7
    /// @dev This function must be checked for overflow before being called
    /// @return The total supply as a ValueX7X7
    function toX7X7(uint256 totalSupply) internal pure returns (ValueX7X7) {
        return totalSupply.scaleUpToX7().scaleUpToX7X7();
    }

    /// @notice Pack values into a SupplyRolloverMultiplier
    /// @param set Boolean flag indicating if the value is set which only happens after the auction becomes fully subscribed,
    ///         at which point the supply schedule becomes deterministic based on the future supply schedule
    /// @param remainingMps The remaining MPS value (24 bits)
    /// @param remainingSupplyX7X7 The remaining supply value (must fit in 231 bits)
    /// @return The packed SupplyRolloverMultiplier
    function packSupplyRolloverMultiplier(bool set, uint24 remainingMps, ValueX7X7 remainingSupplyX7X7)
        internal
        pure
        returns (SupplyRolloverMultiplier)
    {
        uint256 supplyValue = ValueX7X7.unwrap(remainingSupplyX7X7);
        uint256 packed = 0;
        // Set the boolean flag at bit 255
        if (set) {
            packed |= SET_FLAG_MASK;
        }
        // Set remainingMps at bits 254-231
        packed |= uint256(remainingMps) << REMAINING_MPS_BIT_POSITION;
        // Set remainingSupplyX7X7 at bits 230-0
        packed |= supplyValue;
        return SupplyRolloverMultiplier.wrap(packed);
    }

    /// @notice Unpack a SupplyRolloverMultiplier into its components
    /// @param multiplier The packed SupplyRolloverMultiplier
    /// @return isSet The boolean flag
    /// @return remainingMps The remaining MPS value
    /// @return remainingSupplyX7X7 The remaining supply value
    function unpack(SupplyRolloverMultiplier multiplier)
        internal
        pure
        returns (bool isSet, uint24 remainingMps, ValueX7X7 remainingSupplyX7X7)
    {
        uint256 packed = SupplyRolloverMultiplier.unwrap(multiplier);
        isSet = (packed & SET_FLAG_MASK) != 0;
        // Extract remainingMps from bits 254-231
        remainingMps = uint24((packed & REMAINING_MPS_MASK) >> REMAINING_MPS_BIT_POSITION);
        // Extract remainingSupplyX7X7 from bits 230-0
        remainingSupplyX7X7 = ValueX7X7.wrap(packed & REMAINING_SUPPLY_MASK);
    }
}
