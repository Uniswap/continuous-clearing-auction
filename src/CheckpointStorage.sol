// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ICheckpointStorage} from './interfaces/ICheckpointStorage.sol';
import {AuctionStepLib} from './libraries/AuctionStepLib.sol';
import {Bid, BidLib} from './libraries/BidLib.sol';
import {Checkpoint, CheckpointLib} from './libraries/CheckpointLib.sol';
import {FixedPoint128} from './libraries/FixedPoint128.sol';
import {FixedPoint96} from './libraries/FixedPoint96.sol';
import {ValueX7, ValueX7Lib} from './libraries/ValueX7Lib.sol';
import {console} from 'forge-std/console.sol';
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

    /// @inheritdoc ICheckpointStorage
    function currencyRaised() public view returns (uint256) {
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
    /// @return currencySpentX128 The amount of currency spent in X128.128 form
    function _accountFullyFilledCheckpoints(Checkpoint memory upper, Checkpoint memory startCheckpoint, Bid memory bid)
        internal
        pure
        returns (uint256 tokensFilled, uint256 currencySpentX128)
    {
        (tokensFilled, currencySpentX128) = _calculateFill(
            bid,
            upper.cumulativeMpsPerPrice - startCheckpoint.cumulativeMpsPerPrice,
            upper.cumulativeMps - startCheckpoint.cumulativeMps
        );
    }

    /// @notice Calculate the tokens sold and currency spent for a partially filled bid
    /// @param bid The bid
    /// @param tickDemandX128 The total demand at the tick
    /// @param cumulativeCurrencyRaisedAtClearingPriceX7 The cumulative supply sold to the clearing price
    /// @return tokensFilled The tokens sold
    /// @return currencySpentX128 The amount of currency spent in X128.128 form
    function _accountPartiallyFilledCheckpoints(
        Bid memory bid,
        uint256 tickDemandX128,
        ValueX7 cumulativeCurrencyRaisedAtClearingPriceX7
    ) internal pure returns (uint256 tokensFilled, uint256 currencySpentX128) {
        if (tickDemandX128 == 0) return (0, 0);

        // TODO(ez): fix comments
        ValueX7 currencySpentX128_X7 = bid.amountX128.scaleUpToX7().fullMulDiv(
            cumulativeCurrencyRaisedAtClearingPriceX7.mulUint256(FixedPoint128.Q128),
            ValueX7.wrap(tickDemandX128 * bid.mpsRemainingInAuctionAfterSubmission())
        );
        currencySpentX128 = currencySpentX128_X7.scaleDownToUint256();
        tokensFilled = ValueX7.unwrap(
            currencySpentX128_X7.wrapAndFullMulDiv(FixedPoint96.Q96, bid.maxPrice).divUint256(
                FixedPoint128.Q128 * ValueX7Lib.X7
            )
        );
    }

    /// @notice Calculate the tokens filled and currency spent for a bid
    /// @dev This function uses lazy accounting to efficiently calculate fills across time periods without iterating through individual blocks.
    ///      It MUST only be used when the bid's max price is strictly greater than the clearing price throughout the entire period being calculated.
    /// @param bid the bid to evaluate
    /// @param cumulativeMpsPerPriceDelta the cumulative sum of supply to price ratio
    /// @param cumulativeMpsDelta the cumulative sum of mps values across the block range
    /// @return tokensFilled the amount of tokens filled for this bid
    /// @return currencySpentX128 the amount of currency spent by this bid in X128.128 form
    function _calculateFill(Bid memory bid, uint256 cumulativeMpsPerPriceDelta, uint24 cumulativeMpsDelta)
        internal
        pure
        returns (uint256 tokensFilled, uint256 currencySpentX128)
    {
        uint24 mpsRemainingInAuctionAfterSubmission = bid.mpsRemainingInAuctionAfterSubmission();
        // It's possible that bid.amountX128 * cumulativeMpsPerPriceDelta is less than FixedPoint96.Q96 * mpsRemainingInAuction.
        // That means the bid amount was too small to fill any tokens at the prices sold
        tokensFilled = bid.amountX128.fullMulDiv(
            cumulativeMpsPerPriceDelta, FixedPoint96.Q96 * mpsRemainingInAuctionAfterSubmission * FixedPoint128.Q128
        );
        // The currency spent is simply the original currency amount multiplied by the percentage of the auction which the bid was fully filled for
        // and divided by the percentage of the auction which the bid was allocated over
        currencySpentX128 = bid.amountX128.fullMulDivUp(cumulativeMpsDelta, mpsRemainingInAuctionAfterSubmission);
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
