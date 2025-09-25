// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Bid} from './libraries/BidLib.sol';

/// @title BidStorage
/// @notice Manages bid storage and lifecycle
/// @dev Simple CRUD operations with auto-incrementing IDs
abstract contract BidStorage {
    /// @notice Next bid ID to assign
    uint256 public nextBidId;
    /// @notice Bid storage mapping
    mapping(uint256 bidId => Bid bid) public bids;

    /// @notice Retrieves a bid from storage by ID
    /// @param bidId The unique identifier of the bid
    /// @return bid The bid data structure
    function _getBid(uint256 bidId) internal view returns (Bid memory) {
        return bids[bidId];
    }

    /// @notice Create a new bid
    /// @param exactIn Whether the bid is exact in
    /// @param amount The amount of the bid
    /// @param owner The owner of the bid
    /// @param maxPrice The maximum price for the bid
    /// @param startCumulativeMps The cumulative mps at bid creation
    /// @return bid The created bid
    /// @return bidId The assigned bid ID
    function _createBid(bool exactIn, uint256 amount, address owner, uint256 maxPrice, uint24 startCumulativeMps)
        internal
        returns (Bid memory bid, uint256 bidId)
    {
        bid = Bid({
            exactIn: exactIn,
            startBlock: uint64(block.number),
            startCumulativeMps: startCumulativeMps,
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

    /// @notice Updates an existing bid in storage
    /// @dev Used to update bid state during exit/settlement operations
    /// @param bidId The unique identifier of the bid to update
    /// @param bid The updated bid structure
    function _updateBid(uint256 bidId, Bid memory bid) internal {
        bids[bidId] = bid;
    }

    /// @notice Removes a bid from storage (used after settlement)
    /// @param bidId The unique identifier of the bid to delete
    function _deleteBid(uint256 bidId) internal {
        delete bids[bidId];
    }
}
