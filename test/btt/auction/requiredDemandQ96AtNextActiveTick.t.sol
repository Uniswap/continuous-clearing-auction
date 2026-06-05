// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import {AuctionFuzzConstructorParams, BttBase} from '../BttBase.sol';

import {ContinuousClearingAuction} from 'src/ContinuousClearingAuction.sol';

contract RequiredDemandQ96AtNextActiveTickTest is BttBase {
    function test_WhenNextActiveTickPriceIsMaxTickPtr(AuctionFuzzConstructorParams memory _params)
        external
        setupAuctionConstructorParams(_params)
    {
        // it returns 0

        ContinuousClearingAuction auction =
            new ContinuousClearingAuction(_params.token, _params.totalSupply, _params.parameters, address(0));

        assertEq(auction.nextActiveTickPrice(), auction.MAX_TICK_PTR());
        assertEq(auction.requiredDemandQ96AtNextActiveTick(), 0);
    }
}
