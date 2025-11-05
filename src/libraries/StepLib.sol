// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

struct AuctionStep {
    uint24 mps; // Mps to sell per block in the step
    uint64 startBlock; // Start block of the step (inclusive)
    uint64 endBlock; // Ending block of the step (exclusive)
}

/// @notice Library for auction step calculations and parsing
library StepLib {
    using StepLib for *;

    /// @notice The size of a uint64 in bytes
    uint256 public constant UINT64_SIZE = 8;

    /// @notice Error thrown when the offset is too large for the data length
    error StepLib__InvalidOffsetTooLarge();
    /// @notice Error thrown when the offset is not at a step boundary - a uint64 aligned offset
    error StepLib__InvalidOffsetNotAtStepBoundary();

    /// @notice Unpack the mps and block delta from the auction steps data
    function parse(bytes8 data) internal pure returns (uint24 mps, uint40 blockDelta) {
        mps = uint24(bytes3(data));
        blockDelta = uint40(uint64(data));
    }

    /// @notice Load a word at `offset` from data and parse it into mps and blockDelta
    function get(bytes memory data, uint256 offset) internal pure returns (uint24 mps, uint40 blockDelta) {
        // Offset cannot be greater than the data length
        if (offset >= data.length) revert StepLib__InvalidOffsetTooLarge();
        // Offset must be a multiple of a step (uint64 -  uint24|uint40)
        if (offset % UINT64_SIZE != 0) revert StepLib__InvalidOffsetNotAtStepBoundary();

        assembly {
            let packedValue := mload(add(add(data, 0x20), offset))
            packedValue := shr(192, packedValue)
            mps := shr(40, packedValue)
            blockDelta := and(packedValue, 0xFFFFFFFFFF)
        }
    }
}
