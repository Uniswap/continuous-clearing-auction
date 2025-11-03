// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import {Auction} from 'src/Auction.sol';
import {AuctionParameters} from 'src/interfaces/IAuction.sol';

contract MockAuction is Auction {
    constructor(address _token, uint128 _totalSupply, AuctionParameters memory _parameters)
        Auction(_token, _totalSupply, _parameters)
    {}

    function modifier_onlyAfterAuctionIsOver() external onlyAfterAuctionIsOver {}

    function modifier_onlyAfterClaimBlock() external onlyAfterClaimBlock {}

    function modifier_onlyActiveAuction() external onlyActiveAuction {}
}
