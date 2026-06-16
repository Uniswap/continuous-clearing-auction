// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import {AuctionFuzzConstructorParams, BttBase} from 'btt/BttBase.sol';
import {MockContinuousClearingAuction} from 'btt/mocks/MockContinuousClearingAuction.sol';
import {IAuctionStorage} from 'continuous-clearing-auction/interfaces/IAuctionStorage.sol';
import {IContinuousClearingAuction} from 'continuous-clearing-auction/interfaces/IContinuousClearingAuction.sol';
import {IStepStorage} from 'continuous-clearing-auction/interfaces/IStepStorage.sol';
import {IERC20Minimal} from 'continuous-clearing-auction/interfaces/external/IERC20Minimal.sol';
import {Checkpoint} from 'continuous-clearing-auction/libraries/CheckpointLib.sol';
import {ConstantsLib} from 'continuous-clearing-auction/libraries/ConstantsLib.sol';
import {FixedPoint96} from 'continuous-clearing-auction/libraries/FixedPoint96.sol';
import {MaxBidPriceLib} from 'continuous-clearing-auction/libraries/MaxBidPriceLib.sol';
import {ERC20Mock} from 'openzeppelin-contracts/contracts/mocks/token/ERC20Mock.sol';
import {FixedPointMathLib} from 'solady/utils/FixedPointMathLib.sol';

contract SweepUnsoldTokensTest is BttBase {
    function test_WhenAuctionNotOver(AuctionFuzzConstructorParams memory _params, uint256 _blockNumber) external {
        // it reverts with {AuctionIsNotOver}

        AuctionFuzzConstructorParams memory mParams = validAuctionConstructorInputs(_params);
        MockContinuousClearingAuction auction =
            new MockContinuousClearingAuction(mParams.token, mParams.totalSupply, mParams.parameters, address(0));

        uint256 blockNumber = bound(_blockNumber, 0, mParams.parameters.endBlock - 1);

        vm.roll(blockNumber);

        vm.prank(mParams.parameters.tokensRecipient);
        vm.expectRevert(IStepStorage.AuctionIsNotOver.selector);
        auction.sweepUnsoldTokens();
    }

    modifier whenAuctionIsOver() {
        _;
    }

    function test_GivenPreviouslySwept(AuctionFuzzConstructorParams memory _params, uint256 _blockNumber)
        external
        whenAuctionIsOver
    {
        // it reverts with {CannotSweepTokens}

        AuctionFuzzConstructorParams memory mParams = validAuctionConstructorInputs(_params);
        mParams.parameters.requiredCurrencyRaised = 1;
        mParams.token = address(new ERC20Mock());

        MockContinuousClearingAuction auction =
            new MockContinuousClearingAuction(mParams.token, mParams.totalSupply, mParams.parameters, address(0));

        uint256 blockNumber = bound(_blockNumber, mParams.parameters.endBlock, type(uint64).max);

        ERC20Mock(mParams.token).mint(address(auction), requiredTokenDeposit(mParams));
        auction.onTokensReceived();

        vm.roll(blockNumber);
        vm.prank(mParams.parameters.tokensRecipient);
        auction.sweepUnsoldTokens();

        vm.prank(mParams.parameters.tokensRecipient);
        vm.expectRevert(IAuctionStorage.CannotSweepTokens.selector);
        auction.sweepUnsoldTokens();
    }

    modifier givenNotPreviouslySwept() {
        _;
    }

    function test_GivenGraduated(
        AuctionFuzzConstructorParams memory _params,
        uint128 _requiredCurrencyRaised,
        uint128 _bidAmount
    ) external whenAuctionIsOver givenNotPreviouslySwept {
        // it sweeps 0 tokens
        // it writes sweepUnsoldTokensBlock
        // it does NOT call transfer
        // it emits {TokensSwept}
        // it only has dust after bids are claimed

        // Mostly the same as what is in isGraduated.sol, @todo reuse where possible

        alice = makeAddr('alice');

        AuctionFuzzConstructorParams memory mParams = validAuctionConstructorInputs(_params);
        mParams.token = address(new ERC20Mock());
        mParams.parameters.currency = address(0);
        mParams.parameters.validationHook = address(0);
        mParams.totalSupply = uint128(bound(mParams.totalSupply, 1, ConstantsLib.MAX_TOTAL_SUPPLY));
        mParams.parameters.tickSpacing = bound(mParams.parameters.tickSpacing, 2, type(uint24).max) * FixedPoint96.Q96;
        mParams.parameters.floorPrice = bound(mParams.parameters.floorPrice, 1, 100) * mParams.parameters.tickSpacing;

        uint256 computedMaxBidPrice = MaxBidPriceLib.maxBidPrice(mParams.totalSupply);
        vm.assume(mParams.parameters.floorPrice + mParams.parameters.tickSpacing <= computedMaxBidPrice);

        mParams.parameters.requiredCurrencyRaised = uint128(
            bound(
                _requiredCurrencyRaised, 1, mParams.totalSupply * mParams.parameters.floorPrice / FixedPoint96.Q96 - 1
            )
        );

        MockContinuousClearingAuction auction =
            new MockContinuousClearingAuction(mParams.token, mParams.totalSupply, mParams.parameters, address(0));

        ERC20Mock(mParams.token).mint(address(auction), requiredTokenDeposit(mParams));
        auction.onTokensReceived();

        vm.roll(auction.startBlock());

        uint256 maxPrice = mParams.parameters.floorPrice + mParams.parameters.tickSpacing;
        uint128 bidAmount = uint128(
            bound(
                _bidAmount,
                (mParams.totalSupply + 1) * mParams.parameters.floorPrice / FixedPoint96.Q96,
                type(uint128).max
            )
        );

        vm.deal(address(this), bidAmount);
        uint256 bidId = auction.submitBid{value: bidAmount}(maxPrice, bidAmount, alice, bytes(''));

        vm.roll(auction.endBlock());
        Checkpoint memory checkpoint = auction.checkpoint();

        assertTrue(auction.isGraduated(), 'auction is not graduated');

        assertGe(maxPrice, checkpoint.clearingPrice, 'the clearing price rounded upwards to bigger than bids');

        if (maxPrice > checkpoint.clearingPrice) {
            auction.exitBid(bidId);
        } else if (maxPrice == checkpoint.clearingPrice) {
            auction.exitPartiallyFilledBid(bidId, auction.startBlock(), 0);
        } else {
            revert('the clearing price rounded downwards to smaller than bids');
        }

        uint256 recipientBalanceBefore = ERC20Mock(mParams.token).balanceOf(mParams.parameters.tokensRecipient);

        vm.record();
        vm.prank(mParams.parameters.tokensRecipient);
        auction.sweepUnsoldTokens();

        assertEq(auction.sweepUnsoldTokensBlock(), block.number);

        uint256 swept = ERC20Mock(mParams.token).balanceOf(mParams.parameters.tokensRecipient) - recipientBalanceBefore;
        assertApproxEqAbs(swept, 0, MAX_ALLOWABLE_DUST_WEI, 'swept more than dust');

        vm.roll(auction.claimBlock());
        auction.claimTokens(bidId);

        assertApproxEqAbs(
            ERC20Mock(mParams.token).balanceOf(address(auction)),
            0,
            MAX_ALLOWABLE_DUST_WEI,
            'more than dust left in the contract'
        );
    }

    function test_GivenNotGraduated(
        AuctionFuzzConstructorParams memory _params,
        uint128 _requiredCurrencyRaised,
        uint128 _bidAmount
    ) external whenAuctionIsOver givenNotPreviouslySwept {
        // it sweeps total supply tokens
        // it writes sweepUnsoldTokensBlock
        // it calls transfer
        // it emits {TokensSwept}
        // it have no balance
        // it has increased the balance of the tokens recipient

        // Mostly the same as what is in isGraduated.sol, @todo reuse where possible

        alice = makeAddr('alice');

        AuctionFuzzConstructorParams memory mParams = validAuctionConstructorInputs(_params);
        mParams.token = address(new ERC20Mock());
        mParams.parameters.currency = address(0);
        mParams.parameters.validationHook = address(0);
        mParams.totalSupply = uint128(bound(mParams.totalSupply, 1, ConstantsLib.MAX_TOTAL_SUPPLY));
        mParams.parameters.tickSpacing = bound(mParams.parameters.tickSpacing, 2, type(uint24).max) * FixedPoint96.Q96;
        mParams.parameters.floorPrice = bound(mParams.parameters.floorPrice, 1, 100) * mParams.parameters.tickSpacing;

        uint256 computedMaxBidPrice = MaxBidPriceLib.maxBidPrice(mParams.totalSupply);
        vm.assume(mParams.parameters.floorPrice + mParams.parameters.tickSpacing <= computedMaxBidPrice);

        mParams.parameters.requiredCurrencyRaised = uint128(
            bound(
                _requiredCurrencyRaised, 2, mParams.totalSupply * mParams.parameters.floorPrice / FixedPoint96.Q96 - 1
            )
        );

        MockContinuousClearingAuction auction =
            new MockContinuousClearingAuction(mParams.token, mParams.totalSupply, mParams.parameters, address(0));

        ERC20Mock(mParams.token).mint(address(auction), requiredTokenDeposit(mParams));
        auction.onTokensReceived();

        vm.roll(auction.startBlock());

        uint256 maxPrice = mParams.parameters.floorPrice + mParams.parameters.tickSpacing;
        uint128 bidAmount = uint128(bound(_bidAmount, 1, mParams.parameters.requiredCurrencyRaised - 1));

        vm.deal(address(this), bidAmount);

        uint256 bidId = auction.submitBid{value: bidAmount}(maxPrice, bidAmount, alice, bytes(''));

        vm.roll(auction.endBlock());
        Checkpoint memory checkpoint = auction.checkpoint();

        assertGe(maxPrice, checkpoint.clearingPrice, 'the clearing price rounded upwards to bigger than bids');

        if (maxPrice > checkpoint.clearingPrice) {
            auction.exitBid(bidId);
        } else if (maxPrice == checkpoint.clearingPrice) {
            auction.exitPartiallyFilledBid(bidId, auction.startBlock(), 0);
        } else {
            revert('the clearing price rounded downwards to smaller than bids');
        }

        uint256 expectedSweep = mParams.totalSupply;
        vm.expectEmit(true, true, true, true, address(auction));
        emit IAuctionStorage.TokensSwept(mParams.parameters.tokensRecipient, expectedSweep);
        vm.record();
        vm.prank(mParams.parameters.tokensRecipient);
        auction.sweepUnsoldTokens();

        if (!isCoverage()) {
            {
                (, bytes32[] memory writes) = vm.accesses(address(auction));
                assertEq(writes.length, 1);
            }
            if (expectedSweep > 0) {
                (, bytes32[] memory writes) = vm.accesses(address(mParams.token));
                assertEq(writes.length, 2);
            }
        }

        assertEq(auction.sweepUnsoldTokensBlock(), block.number);

        assertEq(ERC20Mock(mParams.token).balanceOf(address(auction)), 0, 'tokens left in contract');
        assertEq(
            ERC20Mock(mParams.token).balanceOf(address(mParams.parameters.tokensRecipient)),
            expectedSweep,
            'tokens not transferred to recipient'
        );
    }

    function test_WhenCallerIsNotAuthorized(AuctionFuzzConstructorParams memory _params)
        external
        whenAuctionIsOver
        givenNotPreviouslySwept
    {
        // it reverts with {NotAuthorized}

        AuctionFuzzConstructorParams memory mParams = validAuctionConstructorInputs(_params);
        mParams.token = address(new ERC20Mock());
        mParams.parameters.currency = address(0);
        mParams.parameters.validationHook = address(0);
        mParams.totalSupply = uint128(bound(mParams.totalSupply, 1, ConstantsLib.MAX_TOTAL_SUPPLY));
        mParams.parameters.requiredCurrencyRaised = type(uint128).max;
        mParams.parameters.tokensRecipient = makeAddr('tokensRecipient');

        MockContinuousClearingAuction auction =
            new MockContinuousClearingAuction(mParams.token, mParams.totalSupply, mParams.parameters, address(0));

        ERC20Mock(mParams.token).mint(address(auction), mParams.totalSupply);
        auction.onTokensReceived();

        vm.roll(auction.endBlock());
        auction.checkpoint();

        address unauthorizedCaller = makeAddr('unauthorizedCaller');
        vm.prank(unauthorizedCaller);
        vm.expectRevert(
            abi.encodeWithSelector(
                IContinuousClearingAuction.NotAuthorized.selector,
                mParams.parameters.tokensRecipient,
                unauthorizedCaller
            )
        );
        auction.sweepUnsoldTokens();
    }
}
