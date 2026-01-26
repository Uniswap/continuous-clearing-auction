// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import {AuctionFuzzConstructorParams, BttBase} from 'btt/BttBase.sol';
import {MockContinuousClearingAuction} from 'btt/mocks/MockContinuousClearingAuction.sol';
import {ERC20Mock} from 'openzeppelin-contracts/contracts/mocks/token/ERC20Mock.sol';
import {IContinuousClearingAuction} from 'src/interfaces/IContinuousClearingAuction.sol';
import {FixedPoint96} from 'src/libraries/FixedPoint96.sol';

contract ExitBidTest is BttBase {
    function test_WhenBlockLTEndBlock(AuctionFuzzConstructorParams memory _params, uint64 _blockNumber) public {
        // it reverts with {AuctionIsNotOver}

        AuctionFuzzConstructorParams memory mParams = validAuctionConstructorInputs(_params);
        mParams.token = address(new ERC20Mock());
        mParams.parameters.currency = address(0);
        MockContinuousClearingAuction auction =
            new MockContinuousClearingAuction(mParams.token, mParams.totalSupply, mParams.parameters);

        ERC20Mock(mParams.token).mint(address(auction), mParams.totalSupply);
        auction.onTokensReceived();

        _blockNumber = uint64(bound(_blockNumber, 0, mParams.parameters.endBlock - 1));

        vm.roll(_blockNumber);

        vm.expectRevert(IContinuousClearingAuction.AuctionIsNotOver.selector);
        auction.exitBid(0);
    }

    modifier givenAuctionIsOver() {
        _;
    }

    function test_WhenAuctionIsNotGraduated(AuctionFuzzConstructorParams memory _params, uint128 _bidAmount)
        public
        givenAuctionIsOver
    {
        // it fully refunds the bid

        vm.deal(address(this), type(uint256).max);
        vm.assume(_bidAmount > 0);

        AuctionFuzzConstructorParams memory mParams = validAuctionConstructorInputs(_params);
        mParams.token = address(new ERC20Mock());
        mParams.parameters.currency = address(0);
        mParams.parameters.validationHook = address(0);
        // Given not graduated
        mParams.parameters.requiredCurrencyRaised = type(uint128).max;
        MockContinuousClearingAuction auction =
            new MockContinuousClearingAuction(mParams.token, mParams.totalSupply, mParams.parameters);

        ERC20Mock(mParams.token).mint(address(auction), mParams.totalSupply);
        auction.onTokensReceived();

        vm.roll(mParams.parameters.startBlock);

        address owner = makeAddr('owner');
        uint256 maxPrice = mParams.parameters.floorPrice + mParams.parameters.tickSpacing;
        uint256 bidId = auction.submitBid{value: _bidAmount}(maxPrice, _bidAmount, owner, bytes(''));

        vm.roll(mParams.parameters.endBlock);
        auction.checkpoint();

        vm.expectEmit(true, true, true, true);
        emit IContinuousClearingAuction.BidExited(bidId, owner, 0, _bidAmount);
        auction.exitBid(bidId);
    }

    modifier givenAuctionIsGraduated() {
        _;
    }

    function test_WhenBidMaxPriceLTEClearingPrice(AuctionFuzzConstructorParams memory _params)
        public
        givenAuctionIsGraduated
        givenAuctionIsOver
    {
        // it reverts with {CannotExitBid}

        AuctionFuzzConstructorParams memory mParams = validAuctionConstructorInputs(_params);
        mParams.token = address(new ERC20Mock());
        mParams.parameters.currency = address(0);
        mParams.parameters.validationHook = address(0);
        // Given graduated
        mParams.parameters.requiredCurrencyRaised = 0;
        MockContinuousClearingAuction auction =
            new MockContinuousClearingAuction(mParams.token, mParams.totalSupply, mParams.parameters);

        ERC20Mock(mParams.token).mint(address(auction), mParams.totalSupply);
        auction.onTokensReceived();

        vm.roll(mParams.parameters.startBlock);

        uint256 maxPrice = mParams.parameters.floorPrice;
        (, uint256 bidId) = auction.createBid(1, address(this), maxPrice, 1);

        vm.roll(mParams.parameters.endBlock);
        vm.expectRevert(IContinuousClearingAuction.CannotExitBid.selector);
        auction.exitBid(bidId);
    }
}
