// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Tick, TickStorage} from './TickStorage.sol';
import {AuctionStep, AuctionStepLib} from './libraries/AuctionStepLib.sol';
import {Bid, BidLib} from './libraries/BidLib.sol';
import {Checkpoint, CheckpointLib} from './libraries/CheckpointLib.sol';
import {Demand, DemandLib} from './libraries/DemandLib.sol';
import {FixedPoint96} from './libraries/FixedPoint96.sol';

import {console2} from 'forge-std/console2.sol';
import {FixedPointMathLib} from 'solady/utils/FixedPointMathLib.sol';
import {SafeCastLib} from 'solady/utils/SafeCastLib.sol';

/// @title CheckpointStorage
/// @notice Abstract contract for managing auction checkpoints and bid fill calculations
abstract contract CheckpointStorage is TickStorage {
    using FixedPointMathLib for uint256;
    using AuctionStepLib for *;
    using BidLib for *;
    using SafeCastLib for uint256;
    using DemandLib for Demand;

    /// @notice The starting price of the auction
    uint256 public immutable floorPrice;

    /// @notice Storage of checkpoints
    mapping(uint256 blockNumber => Checkpoint) private checkpoints;
    /// @notice The block number of the last checkpointed block
    uint256 public lastCheckpointedBlock;

    constructor(uint256 _floorPrice, uint256 _tickSpacing) TickStorage(_tickSpacing, _floorPrice) {
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
    /// @param _sumDemandAboveClearing The sum of demand above the clearing price
    /// @param _newClearingPrice The new clearing price
    /// @param _blockTokenSupply The token supply at or above tickUpper in the block
    /// @return The updated checkpoint
    function _updateCheckpoint(
        Checkpoint memory _checkpoint,
        AuctionStep memory _step,
        Demand memory _sumDemandAboveClearing,
        uint256 _newClearingPrice,
        uint256 _blockTokenSupply
    ) internal view returns (Checkpoint memory) {
        uint256 resolvedDemandAboveClearing = _sumDemandAboveClearing.resolve(_newClearingPrice);
        // If the clearing price is the floor price, we can only clear the current demand at the floor price
        if (_newClearingPrice == floorPrice) {
            // We can only clear the current demand at the floor price
            _checkpoint.blockCleared = resolvedDemandAboveClearing.applyMpsDenominator(
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

        _checkpoint.clearingPrice = _newClearingPrice;
        _checkpoint.totalCleared += _checkpoint.blockCleared;
        _checkpoint.cumulativeMps += mpsSinceLastCheckpoint;
        _checkpoint.cumulativeMpsPerPrice +=
            CheckpointLib.getMpsPerPrice(mpsSinceLastCheckpoint, _checkpoint.clearingPrice);
        _checkpoint.resolvedDemandAboveClearingPrice = resolvedDemandAboveClearing;
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
    /// @param bid The bid
    /// @return tokensFilled The tokens sold
    /// @return currencySpent The amount of currency spent
    /// @return nextCheckpointBlock The block number of the checkpoint under the bid's max price. Will be 0 if it does not exist.
    function _accountPartiallyFilledCheckpoints(Checkpoint memory lastValidCheckpoint, Bid memory bid)
        internal
        view
        returns (uint256 tokensFilled, uint256 currencySpent, uint256 nextCheckpointBlock)
    {
        uint256 bidDemand = bid.demand();
        uint256 tickDemand = getTick(bid.maxPrice).demand.resolve(bid.maxPrice);
        while (lastValidCheckpoint.prev != 0) {
            Checkpoint memory _next = _getCheckpoint(lastValidCheckpoint.prev);
            (uint256 _tokensFilled, uint256 _currencySpent) = _calculatePartialFill(
                bidDemand,
                tickDemand,
                bid.maxPrice,
                lastValidCheckpoint.totalCleared - _next.totalCleared,
                lastValidCheckpoint.cumulativeMps - _next.cumulativeMps,
                lastValidCheckpoint.resolvedDemandAboveClearingPrice
            );
            tokensFilled += _tokensFilled;
            currencySpent += _currencySpent;
            // Stop searching when the next checkpoint is less than the tick price
            if (_next.clearingPrice < bid.maxPrice) {
                break;
            }
            lastValidCheckpoint = _next;
        }
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
        if (bid.exactIn) {
            tokensFilled = bid.amount.fullMulDiv(cumulativeMpsPerPriceDelta, FixedPoint96.Q96 * mpsDenominator);
            // Round up for currencySpent
            currencySpent = bid.amount.fullMulDivUp(cumulativeMpsDelta, mpsDenominator);
        } else {
            tokensFilled = bid.amount.applyMpsDenominator(cumulativeMpsDelta, mpsDenominator);
            // Round up for currencySpent
            currencySpent = tokensFilled.fullMulDivUp(cumulativeMpsDelta * FixedPoint96.Q96, cumulativeMpsPerPriceDelta);
        }
    }

    /// @notice Calculate the tokens filled and proportion of input used for a partially filled bid
    function _calculatePartialFill(
        uint256 bidDemand,
        uint256 tickDemand,
        uint256 price,
        uint256 supplyOverMps,
        uint24 mpsDelta,
        uint256 resolvedDemandAboveClearingPrice
    ) internal pure returns (uint256 tokensFilled, uint256 currencySpent) {
        // Round up here to decrease the amount sold to the partial fill tick
        uint256 supplySoldToTick =
            supplyOverMps - resolvedDemandAboveClearingPrice.fullMulDivUp(mpsDelta, AuctionStepLib.MPS);
        // Rounds down for tokensFilled
        tokensFilled = supplySoldToTick.fullMulDiv(bidDemand, tickDemand);
        // Round up for currencySpent
        currencySpent = tokensFilled.fullMulDivUp(price, FixedPoint96.Q96);
    }
}
