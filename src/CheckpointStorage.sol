// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

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
    using FixedPointMathLib for *;
    using AuctionStepLib for *;
    using BidLib for *;
    using SafeCastLib for uint256;
    using DemandLib for Demand;
    using CheckpointLib for Checkpoint;

    uint64 public constant MAX_BLOCK_NUMBER = type(uint64).max;

    /// @notice Storage of checkpoints
    mapping(uint64 blockNumber => Checkpoint) private $_checkpoints;
    /// @notice The block number of the last checkpointed block
    uint64 internal $lastCheckpointedBlock;

    /// @inheritdoc ICheckpointStorage
    function latestCheckpoint() public view returns (Checkpoint memory) {
        return _getCheckpoint($lastCheckpointedBlock);
    }

    /// @inheritdoc ICheckpointStorage
    function clearingPrice() public view returns (uint256) {
        return _getCheckpoint($lastCheckpointedBlock).clearingPrice;
    }

    /// @inheritdoc ICheckpointStorage
    function currencyRaised() public view returns (uint128) {
        return _getCheckpoint($lastCheckpointedBlock).getCurrencyRaised();
    }

    /// @notice Get a checkpoint from storage
    function _getCheckpoint(uint64 blockNumber) internal view returns (Checkpoint memory) {
        return $_checkpoints[blockNumber];
    }

    /// @notice Insert a checkpoint into storage
    /// @dev This function updates the prev and next pointers of the latest checkpoint and the new checkpoint
    function _insertCheckpoint(Checkpoint memory checkpoint, uint64 blockNumber) internal {
        uint64 _lastCheckpointedBlock = $lastCheckpointedBlock;
        if (_lastCheckpointedBlock != 0) $_checkpoints[_lastCheckpointedBlock].next = blockNumber;
        checkpoint.prev = _lastCheckpointedBlock;
        checkpoint.next = MAX_BLOCK_NUMBER;
        $_checkpoints[blockNumber] = checkpoint;
        $lastCheckpointedBlock = blockNumber;
    }

    /// @notice Calculate the tokens sold and proportion of input used for a fully filled bid between two checkpoints
    /// @dev This function MUST only be used for checkpoints where the bid's max price is strictly greater than the clearing price
    ///      because it uses lazy accounting to calculate the tokens filled
    /// @param upper The upper checkpoint
    /// @param startCheckpoint The start checkpoint of the bid
    /// @param bid The bid
    /// @return tokensFilled The tokens sold
    /// @return currencySpent The amount of currency spent
    function _accountFullyFilledCheckpoints(Checkpoint memory upper, Checkpoint memory startCheckpoint, Bid memory bid)
        internal
        pure
        returns (uint128 tokensFilled, uint128 currencySpent)
    {
        (tokensFilled, currencySpent) = _calculateFill(
            bid,
            upper.cumulativeMpsPerPrice - startCheckpoint.cumulativeMpsPerPrice,
            upper.cumulativeMps - startCheckpoint.cumulativeMps,
            AuctionStepLib.MPS - startCheckpoint.cumulativeMps
        );
    }

    /// @notice Calculate the tokens sold, proportion of input used, and the block number of the next checkpoint under the bid's max price
    /// @param cumulativeSupplySoldToClearingPrice The cumulative supply sold to the clearing price
    /// @param bidDemand The demand of the bid
    /// @param bidMaxPrice The max price of the bid
    /// @return tokensFilled The tokens sold
    /// @return currencySpent The amount of currency spent
    function _accountPartiallyFilledCheckpoints(
        uint256 cumulativeSupplySoldToClearingPrice,
        uint128 bidDemand,
        uint128 tickDemand,
        uint256 bidMaxPrice
    ) internal pure returns (uint128 tokensFilled, uint128 currencySpent) {
        if (tickDemand == 0) return (0, 0);
        // Expanded version of the math:
        // tokensFilled = bidDemand * runningPartialFillRate * cumulativeMpsDelta / (MPS * Q96)
        // tokensFilled = bidDemand * (cumulativeSupply * Q96 * MPS / tickDemand * cumulativeMpsDelta) * cumulativeMpsDelta / (mpsDenominator * Q96)
        //              = bidDemand * (cumulativeSupply / tickDemand)
        tokensFilled = uint128(bidDemand.fullMulDiv(cumulativeSupplySoldToClearingPrice, tickDemand));
        currencySpent = uint128(tokensFilled.fullMulDivUp(bidMaxPrice, FixedPoint96.Q96));
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
    ) internal pure returns (uint128 tokensFilled, uint128 currencySpent) {
        tokensFilled = bid.exactIn
            ? uint128(bid.amount.fullMulDiv(cumulativeMpsPerPriceDelta, FixedPoint96.Q96 * mpsDenominator))
            : uint128(bid.amount.fullMulDiv(cumulativeMpsDelta, mpsDenominator));
        // If tokensFilled is 0 then currencySpent must be 0
        if (tokensFilled != 0) {
            currencySpent = bid.exactIn
                ? uint128(bid.amount.fullMulDivUp(cumulativeMpsDelta, mpsDenominator))
                : uint128(tokensFilled.fullMulDivUp(cumulativeMpsDelta * FixedPoint96.Q96, cumulativeMpsPerPriceDelta));
        }
    }

    /// @inheritdoc ICheckpointStorage
    function lastCheckpointedBlock() external view override(ICheckpointStorage) returns (uint64) {
        return $lastCheckpointedBlock;
    }

    /// @inheritdoc ICheckpointStorage
    function checkpoints(uint64 blockNumber) external view override(ICheckpointStorage) returns (Checkpoint memory) {
        return $_checkpoints[blockNumber];
    }
}
