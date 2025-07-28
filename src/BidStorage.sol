// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Bid} from './libraries/BidLib.sol';

abstract contract BidStorage {
    /// @notice The id of the next bid to be created
    uint256 public nextBidId;
    /// @notice The mapping of bid ids to bids
    mapping(uint256 bidId => Bid bid) private bids;

    /// @notice Get a bid from storage
    /// @param bidId The id of the bid to get
    /// @return bid The bid
    function _getBid(uint256 bidId) internal view returns (Bid memory) {
        return bids[bidId];
    }

    /// @notice Create a new bid
    /// @param bid The bid to create
    /// @return bidId The id of the created bid
    function _createBid(Bid memory bid) internal returns (uint256 bidId) {
        bidId = nextBidId;
        bids[bidId] = bid;
        nextBidId++;
    }

    /// @notice Update a bid in storage
    /// @param bidId The id of the bid to update
    /// @param bid The new bid
    function _updateBid(uint256 bidId, Bid memory bid) internal {
        bids[bidId] = bid;
    }
}
