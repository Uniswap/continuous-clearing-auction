// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {AuctionStep} from '../Base.sol';

library AuctionStepLib {
    uint16 public constant BPS = 10_000;

    /// @notice Unpack the bps and block delta from the auction steps data
    function get(bytes memory auctionStepsData, uint256 offset) internal pure returns (uint16 bps, uint48 blockDelta) {
        assembly {
            let packedValue := mload(add(add(auctionStepsData, 0x20), offset))
            packedValue := shr(192, packedValue)
            bps := shr(48, packedValue)
            blockDelta := and(packedValue, 0xFFFFFFFFFFFF)
        }
    }

    /// @notice Resolve the supply per block within a given step
    function resolvedSupply(AuctionStep memory step, uint256 totalSupply, uint256 totalCleared, uint256 sumBps)
        internal
        pure
        returns (uint256)
    {
        return (totalSupply - totalCleared) * step.bps / (BPS - sumBps);
    }

    /// @notice Apply the bps to a value
    /// @dev Requires that value is > BPS to avoid loss of precision
    function applyBps(uint256 value, uint16 bps) internal pure returns (uint256) {
        return bps * value / BPS;
    }
}
