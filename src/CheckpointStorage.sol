// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ICheckpointStorage} from './interfaces/ICheckpointStorage.sol';
import {AuctionStepLib} from './libraries/AuctionStepLib.sol';
import {Bid, BidLib} from './libraries/BidLib.sol';
import {Checkpoint, CheckpointLib} from './libraries/CheckpointLib.sol';
import {FixedPoint96} from './libraries/FixedPoint96.sol';
import {ValueX7, ValueX7Lib} from './libraries/ValueX7Lib.sol';
import {FixedPointMathLib} from 'solady/utils/FixedPointMathLib.sol';
/// @title CheckpointStorage
/// @notice Abstract contract for managing auction checkpoints and bid fill calculations

abstract contract CheckpointStorage is ICheckpointStorage {
    using FixedPointMathLib for *;
    using AuctionStepLib for *;
    using BidLib for *;
    using CheckpointLib for Checkpoint;
    using ValueX7Lib for *;

    /// @notice Maximum block number value used as sentinel for last checkpoint
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
    /// @return currencySpentQ96 The amount of currency spent in Q96 form
    function _accountFullyFilledCheckpoints(Checkpoint memory upper, Checkpoint memory startCheckpoint, Bid memory bid)
        internal
        pure
        returns (uint256 tokensFilled, uint256 currencySpentQ96)
    {
        (tokensFilled, currencySpentQ96) = _calculateFill(
            bid,
            upper.cumulativeMpsPerPrice - startCheckpoint.cumulativeMpsPerPrice,
            upper.cumulativeMps - startCheckpoint.cumulativeMps
        );
    }

    /// @notice Calculate the tokens sold and currency spent for a partially filled bid
    /// @param bid The bid
    /// @param tickDemandQ96 The total demand at the tick
    /// @param currencyRaisedAtClearingPriceQ96_X7 The cumulative supply sold to the clearing price
    /// @return tokensFilled The tokens sold
    /// @return currencySpentQ96 The amount of currency spent in Q96 form
    function _accountPartiallyFilledCheckpoints(
        Bid memory bid,
        uint256 tickDemandQ96,
        ValueX7 currencyRaisedAtClearingPriceQ96_X7
    ) internal pure returns (uint256 tokensFilled, uint256 currencySpentQ96) {
        if (tickDemandQ96 == 0) return (0, 0);

        // tickDemandQ96 is a summation of bid effective amounts, so we must scale up the bid
        // by 1e7 and divide by `mpsRemainingInAuctionAfterSubmission` such that we can
        // apply the ratio of the bid demand to the tick demand to the currencyRaisedAtClearingPriceQ96_X7
        ValueX7 currencySpentQ96_X7 = bid.amountQ96.scaleUpToX7()
            .fullMulDivUp(
                currencyRaisedAtClearingPriceQ96_X7,
                ValueX7.wrap(tickDemandQ96 * bid.mpsRemainingInAuctionAfterSubmission())
            );
        // The currency spent ValueX7 is then scaled down to a uint256
        currencySpentQ96 = currencySpentQ96_X7.scaleDownToUint256();
        // The tokens filled uses the currencySpent ValueX7 value and scales down to a uint256
        tokensFilled = currencySpentQ96_X7.divUint256(bid.maxPrice).scaleDownToUint256();
    }

    /// @notice Calculate the tokens filled and currency spent for a bid
    /// @dev This function uses lazy accounting to efficiently calculate fills across time periods without iterating through individual blocks.
    ///      It MUST only be used when the bid's max price is strictly greater than the clearing price throughout the entire period being calculated.
    /// @param bid the bid to evaluate
    /// @param cumulativeMpsPerPriceDelta the cumulative sum of supply to price ratio
    /// @param cumulativeMpsDelta the cumulative sum of mps values across the block range
    /// @return tokensFilled the amount of tokens filled for this bid
    /// @return currencySpentQ96 the amount of currency spent by this bid in Q96 form
    function _calculateFill(Bid memory bid, uint256 cumulativeMpsPerPriceDelta, uint24 cumulativeMpsDelta)
        internal
        pure
        returns (uint256 tokensFilled, uint256 currencySpentQ96)
    {
        uint24 mpsRemainingInAuctionAfterSubmission = bid.mpsRemainingInAuctionAfterSubmission();

        // The currency spent is simply the original currency amount multiplied by the percentage of the auction which the bid was fully filled for
        // and divided by the percentage of the auction which the bid was allocated over
        currencySpentQ96 = bid.amountQ96.fullMulDivUp(cumulativeMpsDelta, mpsRemainingInAuctionAfterSubmission);

        // The tokens filled from the bid are calculated from its effective amount, not the raw amount in the Bid struct
        // As such, we need to multiply it by 1e7 and divide by `mpsRemainingInAuctionAfterSubmission`.
        // We also know that `cumulativeMpsPerPriceDelta` is over `mps` terms, and has not bee divided by 100% (1e7) yet.
        // Thus, we can cancel out the 1e7 terms and just divide by `mpsRemainingInAuctionAfterSubmission`.
        tokensFilled = bid.amountQ96
            .fullMulDiv(
                cumulativeMpsPerPriceDelta,
                (FixedPoint96.Q96 << FixedPoint96.RESOLUTION) * mpsRemainingInAuctionAfterSubmission
            );
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
