// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Bid} from '../libraries/BidLib.sol';

interface IBidStorage {
    /// @notice Get the id of the next bid to be created
    function nextBidId() external view returns (uint256);

    /// @notice Get a bid from storage
    function bids(uint256 bidId) external view returns (Bid memory);
}
