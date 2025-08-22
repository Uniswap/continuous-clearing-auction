// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Auction} from '../../src/Auction.sol';
import {AuctionParameters} from '../../src/Auction.sol';

contract MockAuction is Auction {
    constructor(address _token, uint256 _totalSupply, AuctionParameters memory _parameters)
        Auction(_token, _totalSupply, _parameters)
    {}

    function calculateNewClearingPrice(uint256 minimumClearingPrice, uint256 blockTokenSupply, uint24 cumulativeMps)
        external
        view
        returns (uint256)
    {
        return _calculateNewClearingPrice(minimumClearingPrice, blockTokenSupply, cumulativeMps);
    }
}
