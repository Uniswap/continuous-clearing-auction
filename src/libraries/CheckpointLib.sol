// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {BidLib} from './BidLib.sol';
import {FixedPointMathLib} from 'solady/utils/FixedPointMathLib.sol';

struct Checkpoint {
    uint256 clearingPrice;
    uint256 blockCleared;
    uint256 totalCleared;
    uint24 cumulativeMps;
    uint24 mps;
    uint256 cumulativeMpsPerPrice;
    uint256 resolvedActiveDemand;
    uint256 prev;
}

/// @title CheckpointLib
library CheckpointLib {
    using FixedPointMathLib for uint256;

    /// @notice Return a new checkpoint after advancing the current checkpoint by a number of blocks
    /// @param checkpoint The checkpoint to transform
    /// @param checkpointBlock The block number of the checkpoint
    /// @param blockDelta The number of blocks to advance
    /// @param mps The number of mps to add
    /// @return The transformed checkpoint
    function transform(Checkpoint memory checkpoint, uint256 checkpointBlock, uint256 blockDelta, uint24 mps)
        internal
        pure
        returns (Checkpoint memory)
    {
        // This is an unsafe cast, but we ensure in the construtor that the max blockDelta (end - start) * mps is always less than 1e7 (100%)
        uint24 deltaMps = uint24(mps * blockDelta);
        return Checkpoint({
            clearingPrice: checkpoint.clearingPrice,
            blockCleared: checkpoint.blockCleared,
            totalCleared: checkpoint.totalCleared + checkpoint.blockCleared * blockDelta,
            cumulativeMps: checkpoint.cumulativeMps + deltaMps,
            mps: mps,
            cumulativeMpsPerPrice: checkpoint.cumulativeMpsPerPrice
                + uint256(deltaMps).fullMulDiv(BidLib.PRECISION, checkpoint.clearingPrice),
            resolvedActiveDemand: checkpoint.resolvedActiveDemand,
            prev: checkpointBlock
        });
    }
}
