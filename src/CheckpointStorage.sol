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
    using CheckpointLib for Checkpoint;

    uint64 public constant MAX_BLOCK_NUMBER = type(uint64).max;

    /// @notice Storage of checkpoints
    mapping(uint64 blockNumber => Checkpoint) public checkpoints;
    /// @notice The block number of the last checkpointed block
    uint64 public lastCheckpointedBlock;

    /// @inheritdoc ICheckpointStorage
    function latestCheckpoint() public view returns (Checkpoint memory) {
        return _getCheckpoint(lastCheckpointedBlock);
    }

    /// @inheritdoc ICheckpointStorage
    function clearingPrice() public view returns (uint256) {
        return _getCheckpoint(lastCheckpointedBlock).clearingPrice;
    }

    /// @inheritdoc ICheckpointStorage
    function currencyRaised() public view returns (uint128) {
        return _getCheckpoint(lastCheckpointedBlock).getCurrencyRaised();
    }

    /// @notice Get a checkpoint from storage
    /// @param blockNumber The block number of the checkpoint to get
    /// @return The checkpoint at the given block number
    function _getCheckpoint(uint64 blockNumber) internal view returns (Checkpoint memory) {
        return checkpoints[blockNumber];
    }

    /// @notice Insert a checkpoint into storage
    /// @dev This function updates the prev and next pointers of the latest checkpoint and the new checkpoint
    /// @param checkpoint The fully populated checkpoint to insert
    /// @param blockNumber The block number of the new checkpoint
    function _insertCheckpoint(Checkpoint memory checkpoint, uint64 blockNumber) internal {
        uint64 _lastCheckpointedBlock = lastCheckpointedBlock;
        if (_lastCheckpointedBlock != 0) checkpoints[_lastCheckpointedBlock].next = blockNumber;
        checkpoint.prev = _lastCheckpointedBlock;
        checkpoint.next = MAX_BLOCK_NUMBER;
        checkpoints[blockNumber] = checkpoint;
        lastCheckpointedBlock = blockNumber;
    }

    /// @notice Calculate the tokens sold and proportion of input used for a fully filled bid between two checkpoints
    /// @dev This function MUST only be used for checkpoints where the bid's max price is strictly greater than the clearing price
    ///      because it uses lazy accounting to calculate the tokens filled
    /// @param upper The upper checkpoint
    /// @param bid The bid
    /// @return tokensFilled The tokens sold
    /// @return currencySpent The amount of currency spent
    function _accountFullyFilledCheckpoints(Checkpoint memory upper, Bid memory bid)
        internal
        view
        returns (uint256 tokensFilled, uint256 currencySpent)
    {
        Checkpoint memory lower = _getCheckpoint(bid.startBlock);
        (tokensFilled, currencySpent) = _calculateFill(
            bid,
            upper.cumulativeMpsPerPrice - lower.cumulativeMpsPerPrice,
            upper.cumulativeMps - lower.cumulativeMps,
            AuctionStepLib.MPS - lower.cumulativeMps
        );
    }

    /// @notice Calculate the tokens sold, proportion of input used, and the block number of the next checkpoint under the bid's max price
    /// @param lastPartiallyFilledCheckpoint The last checkpoint where clearing price is equal to bid.maxPrice
    /// @param bidDemand The demand of the bid
    /// @param tickDemand The demand of the tick
    /// @param bidMaxPrice The max price of the bid
    /// @param cumulativeMpsDelta The cumulative sum of mps values across the block range
    /// @param mpsDenominator The percentage of the auction which the bid was spread over
    /// @return tokensFilled The tokens sold
    /// @return currencySpent The amount of currency spent
    function _accountPartiallyFilledCheckpoints(
        Checkpoint memory lastPartiallyFilledCheckpoint,
        uint256 bidDemand,
        uint256 tickDemand,
        uint256 bidMaxPrice,
        uint24 cumulativeMpsDelta,
        uint24 mpsDenominator
    ) internal pure returns (uint256 tokensFilled, uint256 currencySpent) {
        if (cumulativeMpsDelta == 0 || tickDemand == 0) return (0, 0);
        // Given the sum of the supply sold to the clearing price over time, divide by the tick demand
        uint256 runningPartialFillRate = lastPartiallyFilledCheckpoint.cumulativeSupplySoldToClearingPrice.fullMulDiv(
            FixedPoint96.Q96 * mpsDenominator, tickDemand * cumulativeMpsDelta
        );
        // Shorthand for (bidDemand * cumulativeMpsDelta / mpsDenominator) * runningPartialFillRate / Q96;
        tokensFilled =
            bidDemand.fullMulDiv(runningPartialFillRate * cumulativeMpsDelta, FixedPoint96.Q96 * mpsDenominator);
        currencySpent = tokensFilled.fullMulDivUp(bidMaxPrice, FixedPoint96.Q96);
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
}
