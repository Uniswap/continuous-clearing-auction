// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Bid} from './libraries/BidLib.sol';

abstract contract BidStorage {
    /// @notice The id of the next bid to be created
    uint256 public nextBidId;
    /// @notice The mapping of bid ids to bids
    mapping(uint256 bidId => Bid bid) public bids;

    /// @notice Get a bid from storage
    /// @param bidId The id of the bid to get
    /// @return bid The bid
    function _getBid(uint256 bidId) internal view returns (Bid memory) {
        return bids[bidId];
    }

    /// @notice Create a new bid
    /// @param exactIn Whether the bid is exact in
    /// @param amount The amount of the bid
    /// @param owner The owner of the bid
    /// @param maxPrice The maximum price for the bid
    /// @return bidId The id of the created bid
    function _createBid(bool exactIn, uint256 amount, address owner, uint256 maxPrice)
        internal
        returns (uint256 bidId)
    {
        Bid memory bid = Bid({
            exactIn: exactIn,
            startBlock: uint64(block.number),
            exitedBlock: 0,
            maxPrice: maxPrice,
            amount: amount,
            owner: owner,
            tokensFilled: 0
        });

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

    /// @notice Delete a bid from storage
    /// @param bidId The id of the bid to delete
    function _deleteBid(uint256 bidId) internal {
        delete bids[bidId];
    }
}
