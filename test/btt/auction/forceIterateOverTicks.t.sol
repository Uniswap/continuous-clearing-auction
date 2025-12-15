// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {AuctionFuzzConstructorParams, BttBase} from 'btt/BttBase.sol';
import {MockContinuousClearingAuction} from 'btt/mocks/MockContinuousClearingAuction.sol';
import {ERC20Mock} from 'openzeppelin-contracts/contracts/mocks/token/ERC20Mock.sol';
import {FixedPointMathLib} from 'solady/utils/FixedPointMathLib.sol';
import {IContinuousClearingAuction} from 'src/interfaces/IContinuousClearingAuction.sol';
import {ITickStorage} from 'src/interfaces/ITickStorage.sol';
import {Checkpoint} from 'src/libraries/CheckpointLib.sol';
import {FixedPoint96} from 'src/libraries/FixedPoint96.sol';
import {MaxBidPriceLib} from 'src/libraries/MaxBidPriceLib.sol';

contract ForceIterateOverTicksTest is BttBase {
    function _fuzzPostState(MockContinuousClearingAuction _auction) internal {
        // Fuzz each combination of call patterns of `forceIterateOverTicks`, `checkpoint`
        // The auction state should be the same after each combination of calls
        vm.roll(block.number + 1);
        uint256 snapshotId = vm.snapshot();
        uint256 clearingPrice1 = _auction.forceIterateOverTicks(_auction.MAX_TICK_PTR());
        Checkpoint memory checkpoint1 = _auction.checkpoint();
        vm.revertTo(snapshotId);

        snapshotId = vm.snapshot();
        Checkpoint memory checkpoint2 = _auction.checkpoint();
        uint256 clearingPrice2 = _auction.forceIterateOverTicks(_auction.MAX_TICK_PTR());
        vm.revertTo(snapshotId);

        assertEq(checkpoint1, checkpoint2);
        assertEq(clearingPrice1, clearingPrice2);
    }

    function test_WhenAuctionIsNotActive(AuctionFuzzConstructorParams memory _params, uint256 _untilTickPrice) public {
        // it reverts with {AuctionNotStarted}

        AuctionFuzzConstructorParams memory mParams = validAuctionConstructorInputs(_params);
        mParams.token = address(new ERC20Mock());
        mParams.parameters.currency = address(0);
        mParams.parameters.validationHook = address(0);

        MockContinuousClearingAuction auction =
            new MockContinuousClearingAuction(mParams.token, mParams.totalSupply, mParams.parameters);
        ERC20Mock(mParams.token).mint(address(auction), mParams.totalSupply);
        auction.onTokensReceived();

        vm.roll(mParams.parameters.startBlock - 1);
        vm.expectRevert(IContinuousClearingAuction.AuctionNotStarted.selector);
        auction.forceIterateOverTicks(_untilTickPrice);
    }

    modifier givenAuctionIsActive() {
        _;
    }

    function test_WhenTickPriceIsEqualToMAX_TICK_PTR(AuctionFuzzConstructorParams memory _params, uint8 _n)
        public
        givenAuctionIsActive
        returns (MockContinuousClearingAuction)
    {
        // it iterates over ticks until the MAX_TICK_PTR
        // it sets the clearing price
        // it emits {NextActiveTickUpdated} with the MAX_TICK_PTR
        // it sets the nextActiveTickPrice to the MAX_TICK_PTR

        vm.assume(_n > 0 && _n < type(uint8).max - 1);
        vm.deal(address(this), type(uint256).max);

        AuctionFuzzConstructorParams memory mParams = validAuctionConstructorInputs(_params);
        mParams.token = address(new ERC20Mock());
        mParams.parameters.currency = address(0);
        mParams.parameters.validationHook = address(0);
        // Assume at least 2 blocks between startBlock and endBlock
        vm.assume(mParams.parameters.startBlock + 2 < mParams.parameters.endBlock);
        // Assume at least N ticks are available
        vm.assume(
            mParams.parameters.floorPrice + mParams.parameters.tickSpacing * _n
                < MaxBidPriceLib.maxBidPrice(mParams.totalSupply)
        );
        MockContinuousClearingAuction auction =
            new MockContinuousClearingAuction(mParams.token, mParams.totalSupply, mParams.parameters);

        ERC20Mock(mParams.token).mint(address(auction), mParams.totalSupply);
        auction.onTokensReceived();

        vm.roll(mParams.parameters.startBlock);

        // Intiialize N number of ticks
        for (uint8 i = 1; i <= _n; i++) {
            auction.submitBid{value: 1}(
                mParams.parameters.floorPrice + i * mParams.parameters.tickSpacing, 1, address(this), bytes('')
            );
        }

        // Move the price to maxPrice
        uint256 maxPrice = mParams.parameters.floorPrice + _n * mParams.parameters.tickSpacing;
        uint128 bidAmount = uint128(FixedPointMathLib.fullMulDivUp(mParams.totalSupply, maxPrice, FixedPoint96.Q96));
        auction.submitBid{value: bidAmount}(maxPrice, bidAmount, address(this), bytes(''));

        vm.expectEmit(true, true, true, true);
        emit ITickStorage.NextActiveTickUpdated(auction.MAX_TICK_PTR());
        uint256 clearingPrice = auction.forceIterateOverTicks(auction.MAX_TICK_PTR());
        assertEq(clearingPrice, maxPrice, 'Clearing price is not equal to max price');
        assertEq(auction.clearingPrice(), maxPrice, 'clearingPrice() is not equal to max price');
        assertEq(
            auction.nextActiveTickPrice(), auction.MAX_TICK_PTR(), 'nextActiveTickPrice() is not equal to MAX_TICK_PTR'
        );

        _fuzzPostState(auction);
        return auction;
    }

    /// The same test as above but showing that `forceIterateOverTicks` is idempotent
    function test_IsIdempotent(AuctionFuzzConstructorParams memory _params, uint8 _n) public givenAuctionIsActive {
        // it is idempotent
        MockContinuousClearingAuction auction = test_WhenTickPriceIsEqualToMAX_TICK_PTR(_params, _n);
        uint256 prevClearingPrice = auction.clearingPrice();
        for (uint8 i = 0; i < _n; i++) {
            vm.roll(block.number + 1);
            if (block.number >= auction.endBlock()) {
                break;
            }
            uint256 clearingPrice = auction.forceIterateOverTicks(auction.MAX_TICK_PTR());
            assertEq(clearingPrice, prevClearingPrice, 'Clearing price should not change');
            _fuzzPostState(auction);
        }
    }

    modifier givenTickPriceIsNotEqualToMAX_TICK_PTR(uint256 _untilTickPrice) {
        vm.assume(_untilTickPrice != type(uint256).max);
        _;
    }

    function test_WhenUntilTickPriceIsNotAtTickBoundary(
        AuctionFuzzConstructorParams memory _params,
        uint256 _untilTickPrice
    ) public givenTickPriceIsNotEqualToMAX_TICK_PTR(_untilTickPrice) givenAuctionIsActive {
        // it reverts with {TickPriceNotAtBoundary}

        AuctionFuzzConstructorParams memory mParams = validAuctionConstructorInputs(_params);
        mParams.token = address(new ERC20Mock());
        mParams.parameters.currency = address(0);

        vm.assume(_untilTickPrice % mParams.parameters.tickSpacing != 0);
        MockContinuousClearingAuction auction =
            new MockContinuousClearingAuction(mParams.token, mParams.totalSupply, mParams.parameters);
        ERC20Mock(mParams.token).mint(address(auction), mParams.totalSupply);
        auction.onTokensReceived();

        vm.roll(mParams.parameters.startBlock);

        vm.expectRevert(ITickStorage.TickPriceNotAtBoundary.selector);
        auction.forceIterateOverTicks(_untilTickPrice);

        _fuzzPostState(auction);
    }

    modifier givenUntilTickPriceIsAtATickBoundary() {
        _;
    }

    function test_WhenUntilTickPriceIsNotInitialized(
        AuctionFuzzConstructorParams memory _params,
        uint256 _untilTickPrice
    )
        public
        givenTickPriceIsNotEqualToMAX_TICK_PTR(_untilTickPrice)
        givenUntilTickPriceIsAtATickBoundary
        givenAuctionIsActive
    {
        // it reverts with {TickNotInitialized}

        AuctionFuzzConstructorParams memory mParams = validAuctionConstructorInputs(_params);
        mParams.token = address(new ERC20Mock());
        mParams.parameters.currency = address(0);

        vm.assume(_untilTickPrice % mParams.parameters.tickSpacing == 0);
        vm.assume(_untilTickPrice != mParams.parameters.floorPrice);

        MockContinuousClearingAuction auction =
            new MockContinuousClearingAuction(mParams.token, mParams.totalSupply, mParams.parameters);
        ERC20Mock(mParams.token).mint(address(auction), mParams.totalSupply);
        auction.onTokensReceived();

        vm.roll(mParams.parameters.startBlock);

        // No ticks are initialized yet

        vm.expectRevert(ITickStorage.TickNotInitialized.selector);
        auction.forceIterateOverTicks(_untilTickPrice);

        _fuzzPostState(auction);
    }

    modifier givenUntilTickPriceIsInitialized() {
        _;
    }

    function test_WhenUntilTickPriceIsLTENextActiveTickPrice(
        AuctionFuzzConstructorParams memory _params,
        uint256 _untilTickPrice
    )
        public
        givenTickPriceIsNotEqualToMAX_TICK_PTR(_untilTickPrice)
        givenUntilTickPriceIsInitialized
        givenAuctionIsActive
    {
        // it reverts with {TickHintMustBeGreaterThanNextActiveTickPrice}

        AuctionFuzzConstructorParams memory mParams = validAuctionConstructorInputs(_params);
        mParams.token = address(new ERC20Mock());
        mParams.parameters.currency = address(0);
        mParams.parameters.validationHook = address(0);

        MockContinuousClearingAuction auction =
            new MockContinuousClearingAuction(mParams.token, mParams.totalSupply, mParams.parameters);
        ERC20Mock(mParams.token).mint(address(auction), mParams.totalSupply);
        auction.onTokensReceived();

        vm.roll(mParams.parameters.startBlock);

        uint256 nextActiveTickPrice = mParams.parameters.floorPrice + mParams.parameters.tickSpacing;

        // make a new bid to set nextActiveTickPrice
        auction.submitBid{value: 1}(nextActiveTickPrice, 1, address(this), bytes(''));

        // Revert if equal to the next active tick price
        vm.expectRevert(
            abi.encodeWithSelector(
                IContinuousClearingAuction.TickHintMustBeGreaterThanNextActiveTickPrice.selector,
                nextActiveTickPrice,
                nextActiveTickPrice
            )
        );
        auction.forceIterateOverTicks(nextActiveTickPrice);

        // Revert if less than the next active tick price
        vm.expectRevert(
            abi.encodeWithSelector(
                IContinuousClearingAuction.TickHintMustBeGreaterThanNextActiveTickPrice.selector,
                mParams.parameters.floorPrice,
                nextActiveTickPrice
            )
        );
        auction.forceIterateOverTicks(mParams.parameters.floorPrice);

        _fuzzPostState(auction);
    }

    function test_WhenUntilTickPriceIsGreaterThanNextActiveTickPrice(
        AuctionFuzzConstructorParams memory _params,
        uint8 _n,
        uint8 _m
    ) public givenUntilTickPriceIsInitialized givenAuctionIsActive {
        // it sets the nextActiveTickPrice to the untilTickPrice
        // it sets the clearing price
        // it emits {NextActiveTickUpdated} with the untilTickPrice
        // it sets the nextActiveTickPrice to the untilTickPrice

        vm.deal(address(this), type(uint256).max);
        vm.assume(_n > 0 && _m < _n && _n < type(uint8).max - 1);

        AuctionFuzzConstructorParams memory mParams = validAuctionConstructorInputs(_params);
        mParams.token = address(new ERC20Mock());
        mParams.parameters.currency = address(0);
        mParams.parameters.validationHook = address(0);
        vm.assume(
            mParams.parameters.floorPrice + _n * mParams.parameters.tickSpacing
                < MaxBidPriceLib.maxBidPrice(mParams.totalSupply)
        );

        MockContinuousClearingAuction auction =
            new MockContinuousClearingAuction(mParams.token, mParams.totalSupply, mParams.parameters);
        ERC20Mock(mParams.token).mint(address(auction), mParams.totalSupply);
        auction.onTokensReceived();

        vm.roll(mParams.parameters.startBlock);

        for (uint8 i = 1; i <= _n; i++) {
            auction.submitBid{value: 1}(
                mParams.parameters.floorPrice + i * mParams.parameters.tickSpacing, 1, address(this), bytes('')
            );
        }

        // setup auction to move price up to n
        uint256 maxPrice = mParams.parameters.floorPrice + _n * mParams.parameters.tickSpacing;
        uint128 bidAmount = uint128(FixedPointMathLib.fullMulDivUp(mParams.totalSupply, maxPrice, FixedPoint96.Q96));
        auction.submitBid{value: bidAmount}(maxPrice, bidAmount, address(this), bytes(''));

        uint256 untilTickPrice = mParams.parameters.floorPrice + _bound(_m, 1, _n) * mParams.parameters.tickSpacing;
        vm.assume(untilTickPrice > auction.nextActiveTickPrice());

        vm.roll(block.number + 1);

        vm.expectEmit(true, true, true, true);
        emit ITickStorage.NextActiveTickUpdated(untilTickPrice);
        uint256 clearingPrice = auction.forceIterateOverTicks(untilTickPrice);
        // In this case we only iterated to a price in the middle so the clearing price is greater than the nextActiveTickPrice
        assertGt(clearingPrice, untilTickPrice, 'Clearing price is not greater than untilTickPrice');
        assertGt(auction.clearingPrice(), untilTickPrice, 'clearingPrice() is not greater than untilTickPrice');
        assertEq(auction.nextActiveTickPrice(), untilTickPrice, 'nextActiveTickPrice() is not equal to untilTickPrice');

        _fuzzPostState(auction);
    }
}
