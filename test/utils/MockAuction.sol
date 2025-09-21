// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Auction} from '../../src/Auction.sol';
import {AuctionParameters} from '../../src/Auction.sol';
import {ValueX7} from '../../src/libraries/MPSLib.sol';

contract MockAuction is Auction {
    constructor(address _token, uint256 _totalSupply, AuctionParameters memory _parameters)
        Auction(_token, _totalSupply, _parameters)
    {}

    function calculateNewClearingPrice(uint256 minimumClearingPrice, ValueX7 blockTokenSupply)
        external
        view
        returns (uint256)
    {
        // TODO: needs to be in mps terms
        return _calculateNewClearingPrice(sumDemandAboveClearing, minimumClearingPrice, blockTokenSupply);
    }
}
