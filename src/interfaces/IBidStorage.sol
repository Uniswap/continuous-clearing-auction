// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Bid} from '../libraries/BidLib.sol';

/// @notice Interface for bid storage operations
interface IBidStorage {
    /// @notice Error thrown when doing an operation on a bid that does not exist
    error BidIdDoesNotExist(uint256 bidId);

    /// @notice Get the id of the next bid to be created
    /// @return The id of the next bid to be created
    function nextBidId() external view returns (uint256);

    /// @notice Get a bid from storage
    /// @dev Will revert if the bid does not exist
    /// @param bidId The id of the bid to get
    /// @return The bid
    function bids(uint256 bidId) external view returns (Bid memory);
}
