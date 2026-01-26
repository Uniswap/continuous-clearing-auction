// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {AuctionFuzzConstructorParams, BttBase} from 'btt/BttBase.sol';
import {MockContinuousClearingAuction} from 'btt/mocks/MockContinuousClearingAuction.sol';
import {ERC20Mock} from 'openzeppelin-contracts/contracts/mocks/token/ERC20Mock.sol';
import {IContinuousClearingAuction} from 'src/interfaces/IContinuousClearingAuction.sol';
import {LBPInitializationParams} from 'src/interfaces/external/ILBPInitializer.sol';

contract LBPInitializationParamsTest is BttBase {
    function test_WhenAuctionIsNotFinalized(AuctionFuzzConstructorParams memory _params, uint64 _blockNumber) external {
        // it reverts with {AuctionIsNotFinalized}
        AuctionFuzzConstructorParams memory mParams = validAuctionConstructorInputs(_params);
        mParams.token = address(new ERC20Mock());

        MockContinuousClearingAuction auction =
            new MockContinuousClearingAuction(mParams.token, mParams.totalSupply, mParams.parameters);

        ERC20Mock(mParams.token).mint(address(auction), mParams.totalSupply);
        auction.onTokensReceived();

        _blockNumber = uint64(bound(_blockNumber, mParams.parameters.startBlock, mParams.parameters.endBlock - 1));
        vm.roll(_blockNumber);
        auction.checkpoint();

        vm.expectRevert(IContinuousClearingAuction.AuctionIsNotFinalized.selector);
        auction.lbpInitializationParams();
    }

    modifier givenAuctionIsFinalized() {
        _;
    }

    function test_WhenAuctionIsFinalized(AuctionFuzzConstructorParams memory _params) external givenAuctionIsFinalized {
        // it returns the correct initialization params
        AuctionFuzzConstructorParams memory mParams = validAuctionConstructorInputs(_params);
        mParams.token = address(new ERC20Mock());

        MockContinuousClearingAuction auction =
            new MockContinuousClearingAuction(mParams.token, mParams.totalSupply, mParams.parameters);

        ERC20Mock(mParams.token).mint(address(auction), mParams.totalSupply);
        auction.onTokensReceived();

        vm.roll(auction.endBlock());
        auction.checkpoint();

        LBPInitializationParams memory params = auction.lbpInitializationParams();
        assertEq(params.initialPriceX96, auction.clearingPrice());
        assertEq(params.tokensSold, auction.totalCleared());
        assertEq(params.currencyRaised, auction.currencyRaised());
    }
}
