// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {CheckpointStorage} from 'continuous-clearing-auction/CheckpointStorage.sol';

import {Bid} from 'continuous-clearing-auction/libraries/BidLib.sol';
import {Checkpoint} from 'continuous-clearing-auction/libraries/CheckpointLib.sol';
import {ValueX7} from 'continuous-clearing-auction/libraries/ValueX7Lib.sol';

contract MockCheckpointStorage is CheckpointStorage {
    function insertCheckpoint(Checkpoint memory checkpoint, uint64 blockNumber) external {
        super._insertCheckpoint(checkpoint, blockNumber);
    }

    function getCheckpoint(uint64 blockNumber) external view returns (Checkpoint memory) {
        return super._getCheckpoint(blockNumber);
    }

    function accountFullyFilledCheckpoints(Checkpoint memory upper, Checkpoint memory startCheckpoint, Bid memory bid)
        external
        pure
        returns (uint256 tokensFilled, uint256 currencySpent)
    {
        return super._accountFullyFilledCheckpoints(upper, startCheckpoint, bid);
    }

    function accountPartiallyFilledCheckpoints(
        Bid memory bid,
        uint256 tickDemandQ96,
        ValueX7 currencyRaisedAtClearingPriceQ96_X7
    ) external pure returns (uint256 tokensFilled, uint256 currencySpent) {
        return super._accountPartiallyFilledCheckpoints(bid, tickDemandQ96, currencyRaisedAtClearingPriceQ96_X7);
    }
}
