// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import {AuctionFuzzConstructorParams, BttBase} from '../BttBase.sol';

import {MockContinuousClearingAuction} from 'btt/mocks/MockContinuousClearingAuction.sol';
import {IContinuousClearingAuction} from 'continuous-clearing-auction/interfaces/IContinuousClearingAuction.sol';

contract OnlyAfterAuctionIsOverTest is BttBase {
    function test_WhenBlockNumberLTEndBlock(AuctionFuzzConstructorParams memory _params, uint256 _blockNumber)
        external
    {
        // it reverts with {AuctionIsNotOver}
        AuctionFuzzConstructorParams memory mParams = validAuctionConstructorInputs(_params);

        MockContinuousClearingAuction auction =
            new MockContinuousClearingAuction(mParams.token, mParams.totalSupply, mParams.parameters);

        uint256 blockNumber = bound(_blockNumber, 0, mParams.parameters.endBlock - 1);

        vm.roll(blockNumber);
        vm.expectRevert(IContinuousClearingAuction.AuctionIsNotOver.selector);
        auction.modifier_onlyAfterAuctionIsOver();
    }

    function test_WhenBlockNumberGEEndBlock(AuctionFuzzConstructorParams memory _params, uint256 _blockNumber)
        external
    {
        // it does not revert

        AuctionFuzzConstructorParams memory mParams = validAuctionConstructorInputs(_params);

        MockContinuousClearingAuction auction =
            new MockContinuousClearingAuction(mParams.token, mParams.totalSupply, mParams.parameters);

        uint256 blockNumber = bound(_blockNumber, mParams.parameters.endBlock, type(uint256).max);

        vm.roll(blockNumber);
        auction.modifier_onlyAfterAuctionIsOver();
    }
}
