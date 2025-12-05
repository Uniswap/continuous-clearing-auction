// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import {AuctionFuzzConstructorParams, BttBase} from '../BttBase.sol';
import {MockContinuousClearingAuction} from '../mocks/MockContinuousClearingAuction.sol';
import {ERC20Mock} from 'openzeppelin-contracts/contracts/mocks/token/ERC20Mock.sol';
import {FixedPointMathLib} from 'solady/utils/FixedPointMathLib.sol';
import {Checkpoint} from 'src/CheckpointStorage.sol';
import {IContinuousClearingAuction} from 'src/interfaces/IContinuousClearingAuction.sol';
import {IStepStorage} from 'src/interfaces/IStepStorage.sol';
import {ConstantsLib} from 'src/libraries/ConstantsLib.sol';

contract SubmitBidTest is BttBase {
    function test_WhenAuctionIsNotActive(AuctionFuzzConstructorParams memory _params, uint64 _blockNumber) public {
        // it reverts with {AuctionNotStarted}

        AuctionFuzzConstructorParams memory mParams = validAuctionConstructorInputs(_params);
        mParams.token = address(new ERC20Mock());
        mParams.parameters.currency = address(0);

        MockContinuousClearingAuction auction =
            new MockContinuousClearingAuction(mParams.token, mParams.totalSupply, mParams.parameters);

        ERC20Mock(mParams.token).mint(address(auction), mParams.totalSupply);
        auction.onTokensReceived();

        _blockNumber = uint64(bound(_blockNumber, 0, mParams.parameters.startBlock - 1));
        vm.roll(_blockNumber);
        vm.expectRevert(IContinuousClearingAuction.AuctionNotStarted.selector);
        auction.submitBid{value: 1}(1, 1, address(this), bytes(''));
    }

    modifier givenAuctionIsActive() {
        _;
    }

    function test_WhenBlockNumberGTEEndBlock(AuctionFuzzConstructorParams memory _params, uint64 _blockNumber)
        public
        givenAuctionIsActive
    {
        // it reverts with {AuctionIsOver}

        AuctionFuzzConstructorParams memory mParams = validAuctionConstructorInputs(_params);
        mParams.token = address(new ERC20Mock());
        mParams.parameters.currency = address(0);

        _blockNumber = uint64(bound(_blockNumber, mParams.parameters.endBlock, type(uint64).max));

        MockContinuousClearingAuction auction =
            new MockContinuousClearingAuction(mParams.token, mParams.totalSupply, mParams.parameters);

        ERC20Mock(mParams.token).mint(address(auction), mParams.totalSupply);
        auction.onTokensReceived();

        vm.roll(_blockNumber);
        vm.expectRevert(IStepStorage.AuctionIsOver.selector);
        auction.submitBid{value: 1}(1, 1, address(this), bytes(''));
    }

    modifier givenBlockNumberIsBeforeEndBlock() {
        _;
    }

    function test_WhenBidAmountEqZero(AuctionFuzzConstructorParams memory _params)
        public
        givenBlockNumberIsBeforeEndBlock
    {
        // it reverts with {BidAmountTooSmall}

        AuctionFuzzConstructorParams memory mParams = validAuctionConstructorInputs(_params);
        mParams.token = address(new ERC20Mock());
        mParams.parameters.currency = address(0);

        MockContinuousClearingAuction auction =
            new MockContinuousClearingAuction(mParams.token, mParams.totalSupply, mParams.parameters);

        ERC20Mock(mParams.token).mint(address(auction), mParams.totalSupply);
        auction.onTokensReceived();

        vm.roll(mParams.parameters.startBlock);
        vm.expectRevert(IContinuousClearingAuction.BidAmountTooSmall.selector);
        auction.submitBid{value: 0}(1, 0, address(this), bytes(''));
    }

    modifier givenBidAmountGTZero() {
        _;
    }

    function test_WhenBidOwnerEqZeroAddress(AuctionFuzzConstructorParams memory _params)
        public
        givenBlockNumberIsBeforeEndBlock
        givenBidAmountGTZero
    {
        // it reverts with {BidOwnerCannotBeZeroAddress}

        AuctionFuzzConstructorParams memory mParams = validAuctionConstructorInputs(_params);
        mParams.token = address(new ERC20Mock());
        mParams.parameters.currency = address(0);

        MockContinuousClearingAuction auction =
            new MockContinuousClearingAuction(mParams.token, mParams.totalSupply, mParams.parameters);

        ERC20Mock(mParams.token).mint(address(auction), mParams.totalSupply);
        auction.onTokensReceived();

        vm.roll(mParams.parameters.startBlock);
        vm.expectRevert(IContinuousClearingAuction.BidOwnerCannotBeZeroAddress.selector);
        auction.submitBid{value: 1}(1, 1, address(0), bytes(''));
    }

    modifier givenBidOwnerIsNotZeroAddress() {
        _;
    }

    function test_WhenCurrencyIsZeroAndMsgValueIsNotEqAmount(AuctionFuzzConstructorParams memory _params)
        public
        givenBlockNumberIsBeforeEndBlock
        givenBidOwnerIsNotZeroAddress
        givenBidAmountGTZero
    {
        // it reverts with {InvalidAmount}

        AuctionFuzzConstructorParams memory mParams = validAuctionConstructorInputs(_params);
        mParams.token = address(new ERC20Mock());
        mParams.parameters.currency = address(0);

        MockContinuousClearingAuction auction =
            new MockContinuousClearingAuction(mParams.token, mParams.totalSupply, mParams.parameters);

        ERC20Mock(mParams.token).mint(address(auction), mParams.totalSupply);
        auction.onTokensReceived();

        vm.roll(mParams.parameters.startBlock);
        vm.expectRevert(IContinuousClearingAuction.InvalidAmount.selector);
        auction.submitBid{value: 0}(1, 1, address(this), bytes(''));
    }

    function test_WhenCurrencyIsNotZeroAndMsgValueIsNotZero(AuctionFuzzConstructorParams memory _params)
        public
        givenBlockNumberIsBeforeEndBlock
        givenBidOwnerIsNotZeroAddress
        givenBidAmountGTZero
    {
        // it reverts with {CurrencyIsNotNative}

        AuctionFuzzConstructorParams memory mParams = validAuctionConstructorInputs(_params);
        mParams.token = address(new ERC20Mock());
        mParams.parameters.currency = address(new ERC20Mock());

        MockContinuousClearingAuction auction =
            new MockContinuousClearingAuction(mParams.token, mParams.totalSupply, mParams.parameters);

        ERC20Mock(mParams.token).mint(address(auction), mParams.totalSupply);
        auction.onTokensReceived();

        vm.roll(mParams.parameters.startBlock);
        vm.expectRevert(IContinuousClearingAuction.CurrencyIsNotNative.selector);
        auction.submitBid{value: 1}(1, 1, address(this), bytes(''));
    }
}
