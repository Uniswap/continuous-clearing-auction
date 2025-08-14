// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {TickStorage} from './TickStorage.sol';
import {AuctionStep, AuctionStepLib} from './libraries/AuctionStepLib.sol';
import {Bid, BidLib} from './libraries/BidLib.sol';
import {Checkpoint} from './libraries/CheckpointLib.sol';
import {Tick, TickLib} from './libraries/TickLib.sol';

import {FixedPointMathLib} from 'solady/utils/FixedPointMathLib.sol';
import {SafeCastLib} from 'solady/utils/SafeCastLib.sol';

/// @title CheckpointStorage
/// @notice Abstract contract for managing auction checkpoints and bid fill calculations
abstract contract CheckpointStorage is TickStorage {
    using FixedPointMathLib for uint256;
    using AuctionStepLib for *;
    using BidLib for *;
    using TickLib for Tick;
    using SafeCastLib for uint256;

    /// @notice The starting price of the auction
    uint256 public immutable floorPrice;

    /// @notice Storage of checkpoints
    mapping(uint256 blockNumber => Checkpoint) private checkpoints;
    /// @notice The block number of the last checkpointed block
    uint256 public lastCheckpointedBlock;

    constructor(uint256 _floorPrice, uint256 _tickSpacing) TickStorage(_tickSpacing) {
        floorPrice = _floorPrice;
    }

    /// @notice Get the latest checkpoint at the last checkpointed block
    function latestCheckpoint() public view returns (Checkpoint memory) {
        return checkpoints[lastCheckpointedBlock];
    }

    /// @notice Get the clearing price at the last checkpointed block
    function clearingPrice() public view returns (uint256) {
        return checkpoints[lastCheckpointedBlock].clearingPrice;
    }

    /// @notice Get a checkpoint from storage
    function _getCheckpoint(uint256 blockNumber) internal view returns (Checkpoint memory) {
        return checkpoints[blockNumber];
    }

    /// @notice Insert a checkpoint into storage
    function _insertCheckpoint(Checkpoint memory checkpoint) internal {
        checkpoints[block.number] = checkpoint;
        lastCheckpointedBlock = block.number;
    }

    /// @notice Update the checkpoint
    /// @param _checkpoint The checkpoint to update
    /// @param _blockResolvedDemandAboveClearing The resolved demand above the clearing price in the block
    /// @param _blockTokenSupply The token supply at or above tickUpper in the block
    /// @return The updated checkpoint
    function _updateCheckpoint(
        Checkpoint memory _checkpoint,
        AuctionStep memory _step,
        uint256 _blockResolvedDemandAboveClearing,
        uint256 _blockTokenSupply
    ) internal view returns (Checkpoint memory) {
        // If the clearing price is the floor price, we can only clear the current demand at the floor price
        if (_checkpoint.clearingPrice == floorPrice) {
            // We can only clear the current demand at the floor price
            _checkpoint.blockCleared = _blockResolvedDemandAboveClearing.applyMpsDenominator(
                _step.mps, AuctionStepLib.MPS - _checkpoint.cumulativeMps
            );
        }
        // Otherwise, we can clear the entire supply being sold in the block
        else {
            _checkpoint.blockCleared = _blockTokenSupply;
        }

        uint24 mpsSinceLastCheckpoint = (
            _step.mps
                * (block.number - (_step.startBlock > lastCheckpointedBlock ? _step.startBlock : lastCheckpointedBlock))
        ).toUint24();

        _checkpoint.totalCleared += _checkpoint.blockCleared;
        _checkpoint.cumulativeMps += mpsSinceLastCheckpoint;
        _checkpoint.cumulativeMpsPerPrice +=
            uint256(mpsSinceLastCheckpoint).fullMulDiv(BidLib.PRECISION, _checkpoint.clearingPrice);
        _checkpoint.resolvedDemandAboveClearingPrice = _blockResolvedDemandAboveClearing;
        _checkpoint.mps = _step.mps;
        _checkpoint.prev = lastCheckpointedBlock;

        return _checkpoint;
    }

    /// @notice Calculate the tokens sold and proportion of input used for a fully filled bid between two checkpoints
    /// @dev This function MUST only be used for checkpoints where the bid's max price is strictly greater than the clearing price
    ///      because it uses lazy accounting to calculate the tokens filled
    /// @param upper The upper checkpoint
    /// @param lower The lower checkpoint
    /// @param bid The bid
    /// @return tokensFilled The tokens sold
    /// @return cumulativeMpsDelta The proportion of input used
    function _accountFullyFilledCheckpoints(Checkpoint memory upper, Checkpoint memory lower, Bid memory bid)
        internal
        pure
        returns (uint256 tokensFilled, uint24 cumulativeMpsDelta)
    {
        cumulativeMpsDelta = upper.cumulativeMps - lower.cumulativeMps;
        tokensFilled = bid.calculateFill(
            upper.cumulativeMpsPerPrice - lower.cumulativeMpsPerPrice,
            cumulativeMpsDelta,
            AuctionStepLib.MPS - lower.cumulativeMps
        );
    }

    /// @notice Calculate the tokens sold, proportion of input used, and the block number of the next checkpoint under the bid's max price
    /// @dev This function does an iterative search through the checkpoints and thus is more gas intensive
    /// @param upper The upper checkpoint
    /// @param tick The tick which the bid is at
    /// @param bid The bid
    /// @return tokensFilled The tokens sold
    /// @return cumulativeMpsDelta The proportion of input used
    /// @return nextCheckpointBlock The block number of the checkpoint under the bid's max price. Will be 0 if it does not exist.
    function _accountPartiallyFilledCheckpoints(Checkpoint memory upper, Tick memory tick, Bid memory bid)
        internal
        view
        returns (uint256 tokensFilled, uint24 cumulativeMpsDelta, uint256 nextCheckpointBlock)
    {
        uint256 bidDemand = bid.demand(tick.price, tickSpacing);
        uint256 tickDemand = tick.resolveDemand(tickSpacing);
        while (upper.prev != 0) {
            Checkpoint memory _next = _getCheckpoint(upper.prev);
            // Stop searching when the next checkpoint is less than the tick price
            if (_next.clearingPrice < tick.price) {
                // Upper is the last checkpoint where tick.price == clearingPrice
                // Account for tokens sold in the upperCheckpoint block, since checkpoint ranges are not inclusive [start,end)
                (uint256 _upperCheckpointTokensFilled, uint24 _upperCheckpointSupplyMps) = bidDemand
                    .calculatePartialFill(
                    tickDemand, tickSpacing, upper.blockCleared, upper.mps, upper.resolvedDemandAboveClearingPrice
                );
                tokensFilled += _upperCheckpointTokensFilled;
                cumulativeMpsDelta += _upperCheckpointSupplyMps;
                break;
            }
            (uint256 _tokensFilled, uint24 _cumulativeMpsDelta) = bidDemand.calculatePartialFill(
                tickDemand,
                tickSpacing,
                upper.totalCleared - _next.totalCleared,
                upper.cumulativeMps - _next.cumulativeMps,
                upper.resolvedDemandAboveClearingPrice
            );
            tokensFilled += _tokensFilled;
            cumulativeMpsDelta += _cumulativeMpsDelta;
            upper = _next;
        }
        return (tokensFilled, cumulativeMpsDelta, upper.prev);
    }
}
