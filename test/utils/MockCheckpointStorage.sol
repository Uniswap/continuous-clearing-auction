// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {CheckpointStorage} from '../../src/CheckpointStorage.sol';
import {Bid} from '../../src/libraries/BidLib.sol';
import {Checkpoint} from '../../src/libraries/CheckpointLib.sol';
import {ValueX7} from '../../src/libraries/ValueX7Lib.sol';

contract MockCheckpointStorage is CheckpointStorage {
    function getCheckpoint(uint64 blockNumber) external view returns (Checkpoint memory) {
        return _getCheckpoint(blockNumber);
    }

    function insertCheckpoint(Checkpoint memory checkpoint, uint64 blockNumber) external {
        _insertCheckpoint(checkpoint, blockNumber);
    }

    function accountFullyFilledCheckpoints(Checkpoint memory upper, Checkpoint memory startCheckpoint, Bid memory bid)
        public
        pure
        returns (uint256 tokensFilled, uint256 currencySpent)
    {
        return _accountFullyFilledCheckpoints(upper, startCheckpoint, bid);
    }

    function accountPartiallyFilledCheckpoints(
        Bid memory bid,
        uint256 tickDemandX128,
        ValueX7 currencyRaisedAtClearingPriceX128_X7
    ) public pure returns (uint256 tokensFilled, uint256 currencySpent) {
        return _accountPartiallyFilledCheckpoints(bid, tickDemandX128, currencyRaisedAtClearingPriceX128_X7);
    }

    function calculateFill(Bid memory bid, uint256 cumulativeMpsPerPriceDelta, uint24 cumulativeMpsDelta)
        external
        pure
        returns (uint256 tokensFilled, uint256 currencySpent)
    {
        return _calculateFill(bid, cumulativeMpsPerPriceDelta, cumulativeMpsDelta);
    }
}
