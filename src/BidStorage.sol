// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IBidStorage} from './interfaces/IBidStorage.sol';
import {Bid} from './libraries/BidLib.sol';

/// @notice Abstract contract for managing bid storage
abstract contract BidStorage is IBidStorage {
    /// @notice The id of the next bid to be created
    uint256 private $_nextBidId;
    /// @notice The mapping of bid ids to bids
    mapping(uint256 bidId => Bid bid) private $_bids;

    /// @notice Get a bid from storage
    /// @param bidId The id of the bid to get
    /// @return bid The bid
    function _getBid(uint256 bidId) internal view returns (Bid memory) {
        return $_bids[bidId];
    }

    /// @notice Create a new bid
    /// @param exactIn Whether the bid is exact in
    /// @param amount The amount of the bid
    /// @param owner The owner of the bid
    /// @param maxPrice The maximum price for the bid
    /// @param startCumulativeMps The cumulative mps at the start of the bid
    /// @return bid The created bid
    /// @return bidId The id of the created bid
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

        bidId = $_nextBidId;
        $_bids[bidId] = bid;
        $_nextBidId++;
    }

    /// @notice Update a bid in storage
    /// @param bidId The id of the bid to update
    /// @param bid The new bid
    function _updateBid(uint256 bidId, Bid memory bid) internal {
        $_bids[bidId] = bid;
    }

    /// @notice Delete a bid from storage
    /// @param bidId The id of the bid to delete
    function _deleteBid(uint256 bidId) internal {
        delete $_bids[bidId];
    }

    /// Getters
    /// @inheritdoc IBidStorage
    function nextBidId() external view override(IBidStorage) returns (uint256) {
        return $_nextBidId;
    }

    /// @inheritdoc IBidStorage
    function bids(uint256 bidId) external view override(IBidStorage) returns (Bid memory) {
        return $_bids[bidId];
    }
}
