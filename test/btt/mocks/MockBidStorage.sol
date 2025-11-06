// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Bid, BidStorage} from 'continuous-clearing-auction/BidStorage.sol';

contract MockBidStorage is BidStorage {
    function createBid(uint256 amount, address owner, uint256 maxPrice, uint24 startCumulativeMps)
        external
        returns (Bid memory bid, uint256 bidId)
    {
        return super._createBid(amount, owner, maxPrice, startCumulativeMps);
    }

    function getBid(uint256 bidId) external view returns (Bid memory) {
        return super._getBid(bidId);
    }
}
