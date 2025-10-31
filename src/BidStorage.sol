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
    function _getBid(uint256 bidId) internal view returns (Bid storage) {
        if (bidId >= $_nextBidId) revert BidIdDoesNotExist(bidId);
        return $_bids[bidId];
    }

    /// @notice Create a new bid
    /// @param amount The amount of the bid
    /// @param owner The owner of the bid
    /// @param maxPrice The maximum price for the bid
    /// @param startCumulativeMps The cumulative mps at the start of the bid
    /// @return bid The created bid
    /// @return bidId The id of the created bid
    function _createBid(uint256 amount, address owner, uint256 maxPrice, uint24 startCumulativeMps)
        internal
        returns (Bid memory bid, uint256 bidId)
    {
        bid = Bid({
            startBlock: uint64(block.number),
            startCumulativeMps: startCumulativeMps,
            exitedBlock: 0,
            maxPrice: maxPrice,
            amountQ96: amount,
            owner: owner,
            tokensFilled: 0
        });

        bidId = $_nextBidId;
        $_bids[bidId] = bid;
        $_nextBidId++;
    }

    /// Getters
    /// @inheritdoc IBidStorage
    function nextBidId() external view override(IBidStorage) returns (uint256) {
        return $_nextBidId;
    }

    /// @inheritdoc IBidStorage
    function bids(uint256 bidId) external view override(IBidStorage) returns (Bid memory) {
        return _getBid(bidId);
    }
}
