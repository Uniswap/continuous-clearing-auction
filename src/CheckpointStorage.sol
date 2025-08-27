// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {ICheckpointStorage} from './interfaces/ICheckpointStorage.sol';
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
abstract contract CheckpointStorage is ICheckpointStorage {
    using FixedPointMathLib for uint256;
    using AuctionStepLib for *;
    using BidLib for *;
    using SafeCastLib for uint256;
    using DemandLib for Demand;
    using CheckpointLib for Checkpoint;

    /// @notice Storage of checkpoints
    mapping(uint256 blockNumber => Checkpoint) public checkpoints;
    /// @notice The block number of the last checkpointed block
    uint256 public lastCheckpointedBlock;

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
    /// @param upperCheckpoint The first checkpoint where clearing price is greater than or equal to bid.maxPrice
    ///        this will be equal if the bid is partially filled at the end of the auction
    /// @param bidDemand The demand of the bid
    /// @param bidMaxPrice The max price of the bid
    /// @param cumulativeMpsDelta The cumulative sum of mps values across the block range
    /// @param mpsDenominator The percentage of the auction which the bid was spread over
    /// @return tokensFilled The tokens sold
    /// @return currencySpent The amount of currency spent
    function _accountPartiallyFilledCheckpoints(
        Checkpoint memory upperCheckpoint,
        uint256 tickDemand,
        uint256 bidDemand,
        uint256 bidMaxPrice,
        uint24 cumulativeMpsDelta,
        uint24 mpsDenominator
    ) internal pure returns (uint256 tokensFilled, uint256 currencySpent) {
        uint256 runningWeightedPartialFillRate =
            upperCheckpoint.sumWeightedPartialFillRate / ((tickDemand * cumulativeMpsDelta) / mpsDenominator);
        tokensFilled = ((bidDemand * cumulativeMpsDelta) / mpsDenominator).fullMulDiv(
            runningWeightedPartialFillRate, FixedPoint96.Q96
        );
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

    /// @notice Calculate the partial fill rate for a partially filled bid
    /// @dev All parameters must be over the same number of `mps`
    /// @param supply The supply of the auction
    /// @param resolvedDemandAboveClearingPrice The demand above the clearing price
    /// @param tickDemand The demand of the tick
    /// @return an X96 fixed point number representing the partial fill rate
    function _calculatePartialFillRate(
        uint256 supply,
        uint256 resolvedDemandAboveClearingPrice,
        uint256 tickDemand
    ) internal pure returns (uint256) {
        if (supply == 0 || tickDemand == 0) return 0;
        return (supply - resolvedDemandAboveClearingPrice).fullMulDiv(FixedPoint96.Q96, tickDemand);
    }

    /// @notice Calculate the tokens filled and proportion of input used for a partially filled bid
    function _calculateSumWeightedPartialFillRate(
        uint256 tickDemand,
        uint256 supplyOverMps,
        uint256 resolvedDemandAboveClearingPrice,
        uint24 mpsDelta
    ) internal pure returns (uint256) {
        uint256 tickDemandMps = tickDemand.applyMps(mpsDelta);
        return tickDemandMps * _calculatePartialFillRate(supplyOverMps, resolvedDemandAboveClearingPrice.applyMps(mpsDelta), tickDemandMps);
    }
}
