// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import {AuctionFuzzConstructorParams, BttBase} from 'btt/BttBase.sol';
import {MockContinuousClearingAuction} from 'btt/mocks/MockContinuousClearingAuction.sol';
import {ERC20Mock} from 'openzeppelin-contracts/contracts/mocks/token/ERC20Mock.sol';
import {FixedPointMathLib} from 'solady/utils/FixedPointMathLib.sol';
import {IContinuousClearingAuction} from 'src/interfaces/IContinuousClearingAuction.sol';
import {FixedPoint96} from 'src/libraries/FixedPoint96.sol';
import {MaxBidPriceLib} from 'src/libraries/MaxBidPriceLib.sol';

contract ExitPartiallyFilledBidTest is BttBase {
    function test_WhenBidAlreadyExited(AuctionFuzzConstructorParams memory _params, uint128 _bidAmount) public {
        // it reverts with {BidAlreadyExited}

        vm.deal(address(this), type(uint256).max);
        vm.assume(_bidAmount > 0);

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

        address owner = makeAddr('owner');
        uint256 maxPrice = mParams.parameters.floorPrice + mParams.parameters.tickSpacing;
        uint256 bidId = auction.submitBid{value: _bidAmount}(maxPrice, _bidAmount, owner, bytes(''));

        vm.roll(mParams.parameters.endBlock);
        auction.checkpoint();
        vm.assume(auction.clearingPrice() == maxPrice);

        auction.exitPartiallyFilledBid(bidId, mParams.parameters.startBlock, 0);

        vm.expectRevert(IContinuousClearingAuction.BidAlreadyExited.selector);
        auction.exitPartiallyFilledBid(bidId, mParams.parameters.startBlock, 0);
    }

    modifier givenBidIsNotExited() {
        _;
    }

    function test_WhenAuctionIsNotGraduatedAndBlockLTEndBlock(
        AuctionFuzzConstructorParams memory _params,
        uint128 _bidAmount
    ) public givenBidIsNotExited {
        // it reverts with {CannotPartiallyExitBidBeforeGraduation}

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

        vm.roll(mParams.parameters.endBlock - 1);
        vm.expectRevert(IContinuousClearingAuction.CannotPartiallyExitBidBeforeGraduation.selector);
        auction.exitPartiallyFilledBid(bidId, mParams.parameters.startBlock, 0);
    }

    modifier givenAuctionIsOver() {
        _;
    }

    function test_WhenAuctionIsNotGraduatedAndBlockGTEndBlock(
        AuctionFuzzConstructorParams memory _params,
        uint128 _bidAmount
    ) public givenBidIsNotExited {
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
        auction.exitPartiallyFilledBid(bidId, mParams.parameters.startBlock, 0);
    }

    modifier givenAuctionIsGraduated() {
        _;
    }

    function test_WhenLastFullyFilledCheckpointHintIsInvalid(
        AuctionFuzzConstructorParams memory _params,
        uint128 _bidAmount,
        uint64 _lastFullyFilledCheckpointBlock
    ) public givenBidIsNotExited {
        // it reverts with {InvalidLastFullyFilledCheckpointHint}

        vm.deal(address(this), type(uint256).max);
        vm.assume(_bidAmount > 0);

        AuctionFuzzConstructorParams memory mParams = validAuctionConstructorInputs(_params);
        mParams.token = address(new ERC20Mock());
        mParams.parameters.currency = address(0);
        mParams.parameters.validationHook = address(0);
        // Assume at least 2 blocks between startBlock and endBlock
        vm.assume(mParams.parameters.startBlock + 2 < mParams.parameters.endBlock);
        // Given graduated
        mParams.parameters.requiredCurrencyRaised = 0;
        MockContinuousClearingAuction auction =
            new MockContinuousClearingAuction(mParams.token, mParams.totalSupply, mParams.parameters);

        ERC20Mock(mParams.token).mint(address(auction), mParams.totalSupply);
        auction.onTokensReceived();

        vm.roll(mParams.parameters.startBlock);

        address owner = makeAddr('owner');
        uint256 maxPrice = mParams.parameters.floorPrice + mParams.parameters.tickSpacing;
        // Bid a small amount to ensure that maxPrice == clearing price
        uint256 bidId = auction.submitBid{value: 1}(maxPrice, 1, owner, bytes(''));

        // Invalid as long as not == startBlock
        vm.assume(_lastFullyFilledCheckpointBlock != mParams.parameters.startBlock);

        vm.roll(mParams.parameters.endBlock);
        vm.expectRevert(IContinuousClearingAuction.InvalidLastFullyFilledCheckpointHint.selector);
        auction.exitPartiallyFilledBid(bidId, _lastFullyFilledCheckpointBlock, 0);
    }

    modifier givenLastFullyFilledCheckpointHintIsValid() {
        _;
    }

    function test_WhenOutbidBlockHintIsNotZeroAndIsInvalid(AuctionFuzzConstructorParams memory _params)
        public
        givenBidIsNotExited
        givenLastFullyFilledCheckpointHintIsValid
    {
        // it reverts with {InvalidOutbidBlockCheckpointHint}

        vm.deal(address(this), type(uint256).max);

        AuctionFuzzConstructorParams memory mParams = validAuctionConstructorInputs(_params);
        mParams.token = address(new ERC20Mock());
        mParams.parameters.currency = address(0);
        mParams.parameters.validationHook = address(0);
        // Assume at least 2 blocks between startBlock and endBlock
        vm.assume(mParams.parameters.startBlock + 2 < mParams.parameters.endBlock);
        vm.assume(
            mParams.parameters.floorPrice + mParams.parameters.tickSpacing * 2
                < MaxBidPriceLib.maxBidPrice(mParams.totalSupply)
        );
        // Given graduated
        mParams.parameters.requiredCurrencyRaised = 0;
        MockContinuousClearingAuction auction =
            new MockContinuousClearingAuction(mParams.token, mParams.totalSupply, mParams.parameters);

        ERC20Mock(mParams.token).mint(address(auction), mParams.totalSupply);
        auction.onTokensReceived();

        vm.roll(mParams.parameters.startBlock);

        address owner = makeAddr('owner');
        uint256 maxPrice = mParams.parameters.floorPrice + mParams.parameters.tickSpacing;
        uint256 bidId = auction.submitBid{value: 1}(maxPrice, 1, owner, bytes(''));

        // Bid a second bid to ensure that the outbid block hint is invalid
        uint256 maxPrice2 = maxPrice + mParams.parameters.tickSpacing;
        uint128 bidAmount2 = uint128(FixedPointMathLib.fullMulDivUp(mParams.totalSupply, maxPrice2, FixedPoint96.Q96));
        uint256 bidId2 = auction.submitBid{value: bidAmount2}(maxPrice2, bidAmount2, owner, bytes(''));

        vm.roll(mParams.parameters.endBlock - 1);
        auction.checkpoint();

        vm.roll(mParams.parameters.endBlock);
        auction.checkpoint();

        // First bid was outbid by the next block, so the correct outbid block hint is mParams.parameters.endBlock - 1
        vm.expectRevert(IContinuousClearingAuction.InvalidOutbidBlockCheckpointHint.selector);
        auction.exitPartiallyFilledBid(bidId, mParams.parameters.startBlock, mParams.parameters.endBlock);

        // The correct outbid block should be successful
        auction.exitPartiallyFilledBid(bidId, mParams.parameters.startBlock, mParams.parameters.endBlock - 1);

        // The auction should end with the price == the second bid's max price, which requires the outbid block to be zero
        vm.expectRevert(IContinuousClearingAuction.InvalidOutbidBlockCheckpointHint.selector);
        auction.exitPartiallyFilledBid(bidId2, mParams.parameters.startBlock, mParams.parameters.endBlock);
    }

    function test_WhenOutbidBlockHintIsZeroAndAuctionIsNotOver(AuctionFuzzConstructorParams memory _params)
        public
        givenBidIsNotExited
    {
        // it reverts with {CannotPartiallyExitBidBeforeEndBlock}

        vm.deal(address(this), type(uint256).max);

        AuctionFuzzConstructorParams memory mParams = validAuctionConstructorInputs(_params);
        mParams.token = address(new ERC20Mock());
        mParams.parameters.currency = address(0);
        mParams.parameters.validationHook = address(0);
        mParams.parameters.requiredCurrencyRaised = 0;
        vm.assume(mParams.parameters.startBlock + 2 < mParams.parameters.endBlock);
        vm.assume(
            mParams.parameters.floorPrice + mParams.parameters.tickSpacing * 2
                < MaxBidPriceLib.maxBidPrice(mParams.totalSupply)
        );

        MockContinuousClearingAuction auction =
            new MockContinuousClearingAuction(mParams.token, mParams.totalSupply, mParams.parameters);

        ERC20Mock(mParams.token).mint(address(auction), mParams.totalSupply);
        auction.onTokensReceived();

        vm.roll(mParams.parameters.startBlock);

        address owner = makeAddr('owner');
        uint256 maxPrice = mParams.parameters.floorPrice + mParams.parameters.tickSpacing;
        uint256 bidId = auction.submitBid{value: 1}(maxPrice, 1, owner, bytes(''));

        uint256 maxPrice2 = maxPrice + mParams.parameters.tickSpacing;
        uint128 bidAmount2 = uint128(FixedPointMathLib.fullMulDivUp(mParams.totalSupply, maxPrice2, FixedPoint96.Q96));
        auction.submitBid{value: bidAmount2}(maxPrice2, bidAmount2, owner, bytes(''));

        vm.roll(mParams.parameters.endBlock - 1);
        auction.checkpoint();

        vm.expectRevert(IContinuousClearingAuction.CannotPartiallyExitBidBeforeEndBlock.selector);
        auction.exitPartiallyFilledBid(bidId, mParams.parameters.startBlock, 0);
    }

    function test_WhenOutbidBlockHintIsZeroAndFinalCheckpointIsNotEqualToBidMaxPrice(AuctionFuzzConstructorParams memory _params)
        public
        givenBidIsNotExited
        givenAuctionIsGraduated
        givenAuctionIsOver
    {
        // it reverts with {CannotExitBid}

        vm.deal(address(this), type(uint256).max);

        AuctionFuzzConstructorParams memory mParams = validAuctionConstructorInputs(_params);
        mParams.token = address(new ERC20Mock());
        mParams.parameters.currency = address(0);
        mParams.parameters.validationHook = address(0);
        mParams.parameters.requiredCurrencyRaised = 0;
        vm.assume(mParams.parameters.startBlock + 2 < mParams.parameters.endBlock);
        vm.assume(
            mParams.parameters.floorPrice + mParams.parameters.tickSpacing * 2
                < MaxBidPriceLib.maxBidPrice(mParams.totalSupply)
        );

        MockContinuousClearingAuction auction =
            new MockContinuousClearingAuction(mParams.token, mParams.totalSupply, mParams.parameters);

        ERC20Mock(mParams.token).mint(address(auction), mParams.totalSupply);
        auction.onTokensReceived();

        vm.roll(mParams.parameters.startBlock);

        address owner = makeAddr('owner');
        uint256 maxPrice = mParams.parameters.floorPrice + mParams.parameters.tickSpacing;
        uint256 bidId = auction.submitBid{value: 1}(maxPrice, 1, owner, bytes(''));

        // Move price above the initial bid's max price
        uint256 maxPrice2 = maxPrice + mParams.parameters.tickSpacing;
        uint128 bidAmount2 = uint128(FixedPointMathLib.fullMulDivUp(mParams.totalSupply, maxPrice2, FixedPoint96.Q96));
        auction.submitBid{value: bidAmount2}(maxPrice2, bidAmount2, owner, bytes(''));

        vm.roll(mParams.parameters.endBlock);
        auction.checkpoint();

        vm.expectRevert(IContinuousClearingAuction.CannotExitBid.selector);
        auction.exitPartiallyFilledBid(bidId, mParams.parameters.startBlock, 0);
    }
}
