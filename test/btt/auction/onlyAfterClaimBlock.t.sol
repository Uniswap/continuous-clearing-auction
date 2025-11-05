// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import {AuctionFuzzConstructorParams, BttBase} from '../BttBase.sol';

import {MockAuction} from 'btt/mocks/MockAuction.sol';
import {IAuction} from 'src/interfaces/IAuction.sol';

contract OnlyAfterClaimBlockTest is BttBase {
    function test_WhenBlockNumberLTClaimBlock(AuctionFuzzConstructorParams memory _params, uint256 _blockNumber)
        external
    {
        // it reverts with {NotClaimable}

        // it reverts with {AuctionIsNotOver}
        AuctionFuzzConstructorParams memory mParams = validAuctionConstructorInputs(_params);

        MockAuction auction = new MockAuction(mParams.token, mParams.totalSupply, mParams.parameters);

        uint256 blockNumber = bound(_blockNumber, 0, mParams.parameters.claimBlock - 1);

        vm.roll(blockNumber);
        vm.expectRevert(IAuction.NotClaimable.selector);
        auction.modifier_onlyAfterClaimBlock();
    }

    function test_WhenBlockNumberGEClaimBlock(AuctionFuzzConstructorParams memory _params, uint256 _blockNumber)
        external
    {
        // it does not revert
        AuctionFuzzConstructorParams memory mParams = validAuctionConstructorInputs(_params);

        MockAuction auction = new MockAuction(mParams.token, mParams.totalSupply, mParams.parameters);

        uint256 blockNumber = bound(_blockNumber, mParams.parameters.claimBlock, type(uint256).max);

        vm.roll(blockNumber);
        auction.modifier_onlyAfterClaimBlock();
    }
}
