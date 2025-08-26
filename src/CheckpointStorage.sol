// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {ICheckpointStorage} from './interfaces/ICheckpointStorage.sol';
import {AuctionStep, AuctionStepLib} from './libraries/AuctionStepLib.sol';
import {Bid, BidLib} from './libraries/BidLib.sol';
import {Checkpoint, CheckpointLib} from './libraries/CheckpointLib.sol';
import {Demand, DemandLib} from './libraries/DemandLib.sol';
import {FixedPoint96} from './libraries/FixedPoint96.sol';

import {FixedPointMathLib} from 'solady/utils/FixedPointMathLib.sol';
import {SafeCastLib} from 'solady/utils/SafeCastLib.sol';

/// @title CheckpointStorage
/// @notice Abstract contract for managing auction checkpoints and bid fill calculations
abstract contract CheckpointStorage is ICheckpointStorage {
    using FixedPointMathLib for uint256;
    using AuctionStepLib for *;
    using BidLib for *;
    using SafeCastLib for uint256;
    using DemandLib for Demand;

    /// @notice Storage of checkpoints
    mapping(uint256 blockNumber => Checkpoint) public checkpoints;
    /// @notice The block number of the last checkpointed block
    uint256 public lastCheckpointedBlock;

    /// @inheritdoc ICheckpointStorage
    function latestCheckpoint() public view returns (Checkpoint memory) {
        return checkpoints[lastCheckpointedBlock];
    }

    /// @inheritdoc ICheckpointStorage
    function clearingPrice() public view returns (uint256) {
        return checkpoints[lastCheckpointedBlock].clearingPrice;
    }

    /// @notice Get a checkpoint from storage
    function _getCheckpoint(uint256 blockNumber) internal view returns (Checkpoint memory) {
        return checkpoints[blockNumber];
    }

    /// @notice Insert a checkpoint into storage
    function _insertCheckpoint(Checkpoint memory checkpoint, uint256 blockNumber) internal {
        checkpoints[blockNumber] = checkpoint;
        lastCheckpointedBlock = blockNumber;
    }

    /// @notice Calculate the tokens sold and proportion of input used for a fully filled bid between two checkpoints
    /// @dev This function MUST only be used for checkpoints where the bid's max price is strictly greater than the clearing price
    ///      because it uses lazy accounting to calculate the tokens filled
    /// @param upper The upper checkpoint
    /// @param lower The lower checkpoint
    /// @param bid The bid
    /// @return tokensFilled The tokens sold
    /// @return currencySpent The amount of currency spent
    function _accountFullyFilledCheckpoints(Checkpoint memory upper, Checkpoint memory lower, Bid memory bid)
        internal
        pure
        returns (uint256 tokensFilled, uint256 currencySpent)
    {
        (tokensFilled, currencySpent) = _calculateFill(
            bid,
            upper.cumulativeMpsPerPrice - lower.cumulativeMpsPerPrice,
            upper.cumulativeMps - lower.cumulativeMps,
            AuctionStepLib.MPS - lower.cumulativeMps
        );
    }

    /// @notice Calculate the tokens sold, proportion of input used, and the block number of the next checkpoint under the bid's max price
    /// @dev This function does an iterative search through the checkpoints and thus is more gas intensive
    /// @param lastValidCheckpoint The last checkpoint where the clearing price is == bid.maxPrice
    /// @param bidDemand The demand of the bid
    /// @param tickDemand The demand of the tick
    /// @param bidMaxPrice The max price of the bid
    /// @return tokensFilled The tokens sold
    /// @return currencySpent The amount of currency spent
    /// @return nextCheckpointBlock The block number of the checkpoint under the bid's max price. Will be 0 if it does not exist.
    function _accountPartiallyFilledCheckpoints(
        Checkpoint memory lastValidCheckpoint,
        uint256 bidDemand,
        uint256 tickDemand,
        uint256 bidMaxPrice
    ) internal view returns (uint256 tokensFilled, uint256 currencySpent, uint256 nextCheckpointBlock) {
        while (lastValidCheckpoint.prev != 0) {
            Checkpoint memory _next = _getCheckpoint(lastValidCheckpoint.prev);
            tokensFilled += _calculatePartialFill(
                bidDemand,
                tickDemand,
                lastValidCheckpoint.totalCleared - _next.totalCleared,
                lastValidCheckpoint.cumulativeMps - _next.cumulativeMps,
                lastValidCheckpoint.resolvedDemandAboveClearingPrice
            );
            // Stop searching when the next checkpoint is less than the tick price
            if (_next.clearingPrice < bidMaxPrice) {
                break;
            }
            lastValidCheckpoint = _next;
        }
        // Round up at the end to avoid rounding too early
        currencySpent = tokensFilled.fullMulDivUp(bidMaxPrice, FixedPoint96.Q96);
        return (tokensFilled, currencySpent, lastValidCheckpoint.prev);
    }

    /// @notice Calculate the tokens filled and currency spent for a bid
    /// @dev This function uses lazy accounting to efficiently calculate fills across time periods without iterating through individual blocks.
    ///      It MUST only be used when the bid's max price is strictly greater than the clearing price throughout the entire period being calculated.
    /// @param bid the bid to evaluate
    /// @param cumulativeMpsPerPriceDelta the cumulative sum of supply to price ratio
    /// @param cumulativeMpsDelta the cumulative sum of mps values across the block range
    /// @param mpsDenominator the percentage of the auction which the bid was spread over
    /// @return tokensFilled the amount of tokens filled for this bid
    /// @return currencySpent the amount of currency spent by this bid
    function _calculateFill(
        Bid memory bid,
        uint256 cumulativeMpsPerPriceDelta,
        uint24 cumulativeMpsDelta,
        uint24 mpsDenominator
    ) internal pure returns (uint256 tokensFilled, uint256 currencySpent) {
        tokensFilled = bid.exactIn
            ? bid.amount.fullMulDiv(cumulativeMpsPerPriceDelta, FixedPoint96.Q96 * mpsDenominator)
            : bid.amount * cumulativeMpsDelta / mpsDenominator;
        // If tokensFilled is 0 then currencySpent must be 0
        if (tokensFilled != 0) {
            currencySpent = bid.exactIn
                ? bid.amount * cumulativeMpsDelta / mpsDenominator
                : tokensFilled.fullMulDivUp(cumulativeMpsDelta * FixedPoint96.Q96, cumulativeMpsPerPriceDelta);
        }
    }

    /// @notice Calculate the tokens filled and proportion of input used for a partially filled bid
    function _calculatePartialFill(
        uint256 bidDemand,
        uint256 tickDemand,
        uint256 supplyOverMps,
        uint24 mpsDelta,
        uint256 resolvedDemandAboveClearingPrice
    ) internal pure returns (uint256 tokensFilled) {
        // Round up here to decrease the amount sold to the partial fill tick
        uint256 supplySoldToTick =
            supplyOverMps - resolvedDemandAboveClearingPrice.fullMulDivUp(mpsDelta, AuctionStepLib.MPS);
        // Rounds down for tokensFilled
        tokensFilled = supplySoldToTick.fullMulDiv(bidDemand, tickDemand);
    }
}
