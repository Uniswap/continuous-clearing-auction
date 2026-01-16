// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import {AuctionFuzzConstructorParams, BttBase} from '../BttBase.sol';
import {MockContinuousClearingAuction} from '../mocks/MockContinuousClearingAuction.sol';
import {ERC20Mock} from 'openzeppelin-contracts/contracts/mocks/token/ERC20Mock.sol';
import {FixedPointMathLib} from 'solady/utils/FixedPointMathLib.sol';
import {ReentrancyGuardTransient} from 'solady/utils/ReentrancyGuardTransient.sol';
import {Checkpoint} from 'src/CheckpointStorage.sol';
import {IContinuousClearingAuction} from 'src/interfaces/IContinuousClearingAuction.sol';
import {IStepStorage} from 'src/interfaces/IStepStorage.sol';
import {IValidationHook} from 'src/interfaces/IValidationHook.sol';
import {ConstantsLib} from 'src/libraries/ConstantsLib.sol';
import {ValidationHookLib} from 'src/libraries/ValidationHookLib.sol';
import {AuctionStepsBuilder} from 'test/utils/AuctionStepsBuilder.sol';
import {MockReenteringValidationHook} from 'test/utils/MockReenteringValidationHook.sol';

contract SubmitBidTest is BttBase {
    using AuctionStepsBuilder for bytes;

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

    function test_WhenMaxPriceIsGreaterThanMaxBidPrice(AuctionFuzzConstructorParams memory _params, uint256 _maxPrice)
        public
        givenBlockNumberIsBeforeEndBlock
        givenBidOwnerIsNotZeroAddress
        givenBidAmountGTZero
    {
        // it reverts with {InvalidBidPriceTooHigh}

        AuctionFuzzConstructorParams memory mParams = validAuctionConstructorInputs(_params);
        mParams.token = address(new ERC20Mock());
        mParams.parameters.currency = address(0);

        MockContinuousClearingAuction auction =
            new MockContinuousClearingAuction(mParams.token, mParams.totalSupply, mParams.parameters);

        ERC20Mock(mParams.token).mint(address(auction), mParams.totalSupply);
        auction.onTokensReceived();

        _maxPrice = _bound(_maxPrice, auction.MAX_BID_PRICE() + 1, type(uint256).max);

        vm.roll(mParams.parameters.startBlock);
        vm.expectRevert(
            abi.encodeWithSelector(
                IContinuousClearingAuction.InvalidBidPriceTooHigh.selector, _maxPrice, auction.MAX_BID_PRICE()
            )
        );
        auction.submitBid{value: 1}(_maxPrice, 1, address(this), bytes(''));
    }

    modifier givenMaxPriceIsLTEMaxBidPrice() {
        _;
    }

    function test_WhenValidationHookReverts(AuctionFuzzConstructorParams memory _params, uint256 _maxPrice)
        public
        givenBlockNumberIsBeforeEndBlock
        givenBidOwnerIsNotZeroAddress
        givenBidAmountGTZero
        givenMaxPriceIsLTEMaxBidPrice
    {
        // it reverts with the revert reason of the validation hook
        AuctionFuzzConstructorParams memory mParams = validAuctionConstructorInputs(_params);
        mParams.token = address(new ERC20Mock());
        mParams.parameters.currency = address(0);
        mParams.parameters.validationHook = makeAddr('MockValidationHook');

        MockContinuousClearingAuction auction =
            new MockContinuousClearingAuction(mParams.token, mParams.totalSupply, mParams.parameters);

        ERC20Mock(mParams.token).mint(address(auction), mParams.totalSupply);
        auction.onTokensReceived();

        _maxPrice = _bound(_maxPrice, 1, auction.MAX_BID_PRICE());

        vm.mockCallRevert(
            mParams.parameters.validationHook,
            abi.encodeWithSelector(IValidationHook.validate.selector),
            'REVERT_REASON'
        );

        vm.roll(mParams.parameters.startBlock);
        vm.expectRevert(abi.encodeWithSelector(ValidationHookLib.ValidationHookCallFailed.selector, 'REVERT_REASON'));
        auction.submitBid{value: 1}(_maxPrice, 1, address(this), bytes(''));
    }

    function test_WhenValidationHookReenters(AuctionFuzzConstructorParams memory _params, uint256 _maxPrice)
        public
        givenBlockNumberIsBeforeEndBlock
        givenBidOwnerIsNotZeroAddress
        givenBidAmountGTZero
        givenMaxPriceIsLTEMaxBidPrice
    {
        // it reverts with {Reentrancy}

        AuctionFuzzConstructorParams memory mParams = validAuctionConstructorInputs(_params);
        mParams.token = address(new ERC20Mock());
        mParams.parameters.currency = address(0);
        mParams.parameters.validationHook = address(new MockReenteringValidationHook(address(this)));

        MockContinuousClearingAuction auction =
            new MockContinuousClearingAuction(mParams.token, mParams.totalSupply, mParams.parameters);

        ERC20Mock(mParams.token).mint(address(auction), mParams.totalSupply);
        auction.onTokensReceived();

        _maxPrice = _bound(_maxPrice, 1, auction.MAX_BID_PRICE());

        vm.roll(mParams.parameters.startBlock);
        vm.expectRevert(
            abi.encodeWithSelector(
                ValidationHookLib.ValidationHookCallFailed.selector,
                abi.encodeWithSelector(ReentrancyGuardTransient.Reentrancy.selector)
            )
        );
        auction.submitBid{value: 1}(_maxPrice, 1, address(this), bytes(''));
    }

    modifier givenValidationHookSucceeds() {
        _;
    }

    function test_WhenAuctionIsSoldOut(AuctionFuzzConstructorParams memory _params, uint256 _maxPrice)
        public
        givenBlockNumberIsBeforeEndBlock
        givenBidOwnerIsNotZeroAddress
        givenBidAmountGTZero
        givenMaxPriceIsLTEMaxBidPrice
        givenValidationHookSucceeds
    {
        // it reverts with {AuctionSoldOut}

        AuctionFuzzConstructorParams memory mParams = validAuctionConstructorInputs(_params);
        mParams.token = address(new ERC20Mock());
        mParams.parameters.startBlock = 0;
        mParams.parameters.endBlock = 101;
        mParams.parameters.claimBlock = 102;
        mParams.parameters.currency = address(0);
        mParams.parameters.validationHook = address(0);
        // Mock the supply schedule to be 100e3 mps for 100 blocks, then 0 mps for 1 block
        mParams.parameters.auctionStepsData = AuctionStepsBuilder.init().addStep(100e3, 100).addStep(0, 1);

        MockContinuousClearingAuction auction =
            new MockContinuousClearingAuction(mParams.token, mParams.totalSupply, mParams.parameters);

        ERC20Mock(mParams.token).mint(address(auction), mParams.totalSupply);
        auction.onTokensReceived();

        _maxPrice = _bound(_maxPrice, 1, auction.MAX_BID_PRICE());

        vm.mockCall(
            mParams.parameters.validationHook, abi.encodeWithSelector(IValidationHook.validate.selector), bytes('')
        );

        vm.roll(mParams.parameters.endBlock - 1);
        vm.expectRevert(IContinuousClearingAuction.AuctionSoldOut.selector);
        auction.submitBid{value: 1}(_maxPrice, 1, address(this), bytes(''));
    }
}
