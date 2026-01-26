// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import {AuctionFuzzConstructorParams, BttBase} from '../BttBase.sol';
import {MockContinuousClearingAuction} from '../mocks/MockContinuousClearingAuction.sol';
import {ERC20Mock} from 'openzeppelin-contracts/contracts/mocks/token/ERC20Mock.sol';
import {FixedPointMathLib} from 'solady/utils/FixedPointMathLib.sol';
import {Checkpoint} from 'src/CheckpointStorage.sol';
import {IContinuousClearingAuction} from 'src/interfaces/IContinuousClearingAuction.sol';
import {ITokenCurrencyStorage} from 'src/interfaces/ITokenCurrencyStorage.sol';
import {ConstantsLib} from 'src/libraries/ConstantsLib.sol';
import {FixedPoint96} from 'src/libraries/FixedPoint96.sol';
import {MaxBidPriceLib} from 'src/libraries/MaxBidPriceLib.sol';
import {ValueX7, ValueX7Lib} from 'src/libraries/ValueX7Lib.sol';

contract SweepCurrencyTest is BttBase {
    using ValueX7Lib for *;

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
        auction.sweepCurrency();
    }

    modifier givenEndBlockIsCheckpointed() {
        _;
    }

    function test_WhenAlreadySwept(AuctionFuzzConstructorParams memory _params) public givenEndBlockIsCheckpointed {
        // it reverts with {CannotSweepCurrency}

        AuctionFuzzConstructorParams memory mParams = validAuctionConstructorInputs(_params);
        mParams.token = address(new ERC20Mock());
        mParams.parameters.currency = address(0);
        // Default graduated
        mParams.parameters.requiredCurrencyRaised = 0;
        MockContinuousClearingAuction auction =
            new MockContinuousClearingAuction(mParams.token, mParams.totalSupply, mParams.parameters);

        ERC20Mock(mParams.token).mint(address(auction), mParams.totalSupply);
        auction.onTokensReceived();

        vm.roll(mParams.parameters.endBlock);
        auction.sweepCurrency();

        vm.expectRevert(ITokenCurrencyStorage.CannotSweepCurrency.selector);
        auction.sweepCurrency();
    }

    modifier givenNotPreviouslySwept() {
        _;
    }

    function test_WhenAuctionIsNotGraduated(AuctionFuzzConstructorParams memory _params, uint128 _bidAmount)
        public
        givenEndBlockIsCheckpointed
    {
        // it reverts with {NotGraduated}

        vm.deal(address(this), type(uint256).max);
        vm.assume(_bidAmount > 0);

        AuctionFuzzConstructorParams memory mParams = validAuctionConstructorInputs(_params);
        mParams.token = address(new ERC20Mock());
        mParams.parameters.currency = address(0);
        mParams.parameters.validationHook = address(0);
        vm.assume(mParams.parameters.endBlock > mParams.parameters.startBlock + 1);
        // Make it not graduated by default
        mParams.parameters.requiredCurrencyRaised = type(uint128).max;
        MockContinuousClearingAuction auction =
            new MockContinuousClearingAuction(mParams.token, mParams.totalSupply, mParams.parameters);

        ERC20Mock(mParams.token).mint(address(auction), mParams.totalSupply);
        auction.onTokensReceived();

        vm.roll(mParams.parameters.startBlock);

        address owner = makeAddr('owner');

        // It's impossible to raise more than uint128.max currency given that bids are uint128s and
        // max price must be > 1 (given min tick spacing)

        uint256 maxPrice = mParams.parameters.floorPrice + mParams.parameters.tickSpacing;
        uint256 bidId = auction.submitBid{value: _bidAmount}(maxPrice, _bidAmount, owner, bytes(''));

        vm.roll(mParams.parameters.endBlock);
        auction.exitPartiallyFilledBid(bidId, mParams.parameters.startBlock, 0);

        vm.expectRevert(ITokenCurrencyStorage.NotGraduated.selector);
        auction.sweepCurrency();
    }

    modifier givenAuctionIsGraduated() {
        _;
    }

    function test_WhenAmountGTZero(AuctionFuzzConstructorParams memory _params, uint128 _bidAmount)
        public
        givenAuctionIsGraduated
        givenNotPreviouslySwept
    {
        // it writes sweepCurrencyBlock
        // it transfers amount currency to funds recipient
        // it emits {CurrencySwept}

        vm.deal(address(this), type(uint256).max);
        vm.assume(_bidAmount > 0);

        AuctionFuzzConstructorParams memory mParams = validAuctionConstructorInputs(_params);
        mParams.token = address(new ERC20Mock());
        mParams.parameters.currency = address(0);
        mParams.parameters.requiredCurrencyRaised = 0;
        mParams.parameters.validationHook = address(0);
        mParams.parameters.fundsRecipient = makeAddr('fundsRecipient');
        MockContinuousClearingAuction auction =
            new MockContinuousClearingAuction(mParams.token, mParams.totalSupply, mParams.parameters);

        ERC20Mock(mParams.token).mint(address(auction), mParams.totalSupply);
        auction.onTokensReceived();

        vm.roll(mParams.parameters.startBlock);

        uint256 maxPrice = mParams.parameters.floorPrice + mParams.parameters.tickSpacing;
        auction.submitBid{value: _bidAmount}(maxPrice, _bidAmount, address(this), bytes(''));

        vm.roll(mParams.parameters.endBlock);
        Checkpoint memory checkpoint = auction.checkpoint();
        uint256 expectedCurrencyRaised =
            checkpoint.currencyRaisedAtClearingPriceQ96_X7.divUint256(FixedPoint96.Q96).scaleDownToUint256();
        vm.assume(expectedCurrencyRaised > 0);

        assertEq(auction.sweepCurrencyBlock(), 0);
        assertEq(mParams.parameters.fundsRecipient.balance, 0);

        vm.expectEmit(true, true, true, true);
        emit ITokenCurrencyStorage.CurrencySwept(mParams.parameters.fundsRecipient, expectedCurrencyRaised);
        auction.sweepCurrency();

        assertEq(auction.sweepCurrencyBlock(), block.number);
        assertEq(mParams.parameters.fundsRecipient.balance, expectedCurrencyRaised);
    }

    function test_WhenAmountEQZero(AuctionFuzzConstructorParams memory _params)
        public
        givenAuctionIsGraduated
        givenNotPreviouslySwept
    {
        // it writes sweepCurrencyBlock
        // it does not transfer currency to funds recipient
        // it emits {CurrencySwept}

        AuctionFuzzConstructorParams memory mParams = validAuctionConstructorInputs(_params);
        mParams.token = address(new ERC20Mock());
        mParams.parameters.currency = address(0);
        mParams.parameters.requiredCurrencyRaised = 0;
        mParams.parameters.fundsRecipient = makeAddr('fundsRecipient');
        MockContinuousClearingAuction auction =
            new MockContinuousClearingAuction(mParams.token, mParams.totalSupply, mParams.parameters);

        ERC20Mock(mParams.token).mint(address(auction), mParams.totalSupply);
        auction.onTokensReceived();

        // No bids

        vm.roll(mParams.parameters.endBlock);
        auction.sweepCurrency();

        assertEq(auction.sweepCurrencyBlock(), block.number);
        assertEq(mParams.parameters.fundsRecipient.balance, 0);
    }
}
