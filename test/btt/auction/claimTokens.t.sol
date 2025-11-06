// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import {AuctionFuzzConstructorParams, BttBase} from 'btt/BttBase.sol';
import {MockContinuousClearingAuction} from 'btt/mocks/MockContinuousClearingAuction.sol';
import {IContinuousClearingAuction} from 'continuous-clearing-auction/interfaces/IContinuousClearingAuction.sol';
import {ITokenCurrencyStorage} from 'continuous-clearing-auction/interfaces/ITokenCurrencyStorage.sol';
import {IERC20Minimal} from 'continuous-clearing-auction/interfaces/external/IERC20Minimal.sol';
import {Bid} from 'continuous-clearing-auction/libraries/BidLib.sol';
import {Checkpoint} from 'continuous-clearing-auction/libraries/CheckpointLib.sol';
import {FixedPoint96} from 'continuous-clearing-auction/libraries/FixedPoint96.sol';
import {ERC20Mock} from 'openzeppelin-contracts/contracts/mocks/token/ERC20Mock.sol';
import {FixedPointMathLib} from 'solady/utils/FixedPointMathLib.sol';

contract ClaimTokensTest is BttBase {
    function test_WhenBlockNumberLTClaimBlock(AuctionFuzzConstructorParams memory _params, uint256 _blockNumber)
        external
    {
        // it reverts with {NotClaimable}

        AuctionFuzzConstructorParams memory mParams = validAuctionConstructorInputs(_params);
        MockContinuousClearingAuction auction =
            new MockContinuousClearingAuction(mParams.token, mParams.totalSupply, mParams.parameters);
        uint256 blockNumber = bound(_blockNumber, 0, mParams.parameters.claimBlock - 1);

        vm.roll(blockNumber);
        vm.expectRevert(IContinuousClearingAuction.NotClaimable.selector);
        auction.claimTokens(0);
    }

    modifier givenPastClaimBlock() {
        _;
    }

    function test_WhenNotGraduated(AuctionFuzzConstructorParams memory _params, uint256 _blockNumber)
        external
        givenPastClaimBlock
    {
        // it reverts with {NotGraduated}

        AuctionFuzzConstructorParams memory mParams = validAuctionConstructorInputs(_params);
        mParams.token = address(new ERC20Mock());
        mParams.parameters.currency = address(0);
        mParams.parameters.validationHook = address(0);
        mParams.parameters.requiredCurrencyRaised = 1;
        MockContinuousClearingAuction auction =
            new MockContinuousClearingAuction(mParams.token, mParams.totalSupply, mParams.parameters);

        ERC20Mock(mParams.token).mint(address(auction), mParams.totalSupply);
        auction.onTokensReceived();

        // Pass the claimBlock check
        uint256 blockNumber = bound(_blockNumber, mParams.parameters.claimBlock, type(uint64).max);

        vm.roll(blockNumber);
        vm.expectRevert(ITokenCurrencyStorage.NotGraduated.selector);
        auction.claimTokens(0);
    }

    function test_WhenGraduated(
        AuctionFuzzConstructorParams memory _params,
        uint256 _blockNumber,
        uint128 _bidAmount,
        uint128 _requiredCurrencyRaised
    ) external givenPastClaimBlock {
        // it claims tokens
        // it emits {TokensClaimed}

        alice = makeAddr('alice');

        AuctionFuzzConstructorParams memory mParams = validAuctionConstructorInputs(_params);
        mParams.token = address(new ERC20Mock());
        mParams.parameters.currency = address(0);
        mParams.parameters.validationHook = address(0);
        mParams.parameters.requiredCurrencyRaised = _requiredCurrencyRaised;
        mParams.parameters.fundsRecipient = makeAddr('fundsRecipient');
        mParams.parameters.tokensRecipient = makeAddr('tokensRecipient');
        mParams.parameters.tickSpacing = bound(mParams.parameters.tickSpacing, 2, type(uint24).max) * FixedPoint96.Q96;
        mParams.parameters.floorPrice = bound(mParams.parameters.floorPrice, 1, 100) * mParams.parameters.tickSpacing;
        MockContinuousClearingAuction auction =
            new MockContinuousClearingAuction(mParams.token, mParams.totalSupply, mParams.parameters);

        ERC20Mock(mParams.token).mint(address(auction), mParams.totalSupply);
        auction.onTokensReceived();

        uint256 maxPrice = mParams.parameters.floorPrice + mParams.parameters.tickSpacing;
        uint128 bidAmount = uint128(bound(_bidAmount, mParams.parameters.requiredCurrencyRaised, type(uint128).max));
        uint256 maximumTokensFilled =
            FixedPointMathLib.min(bidAmount * FixedPoint96.Q96 / mParams.parameters.floorPrice, mParams.totalSupply);

        vm.deal(address(this), bidAmount);
        vm.roll(auction.startBlock());
        uint256 bidId = auction.submitBid{value: bidAmount}(maxPrice, bidAmount, alice, bytes(''));

        vm.roll(auction.endBlock());
        Checkpoint memory checkpoint = auction.checkpoint();

        vm.assume(auction.isGraduated());

        if (maxPrice > checkpoint.clearingPrice) {
            auction.exitBid(bidId);
        } else {
            auction.exitPartiallyFilledBid(bidId, auction.startBlock(), 0);
        }

        Bid memory bid = auction.bids(bidId);
        assertLe(bid.tokensFilled, maximumTokensFilled, 'Bid tokens filled must be less than the maximum tokens filled');

        // Assume bid filled some tokens
        vm.assume(bid.tokensFilled > 0);

        uint256 blockNumber = bound(_blockNumber, mParams.parameters.claimBlock, type(uint64).max);

        uint256 aliceTokensBefore = ERC20Mock(mParams.token).balanceOf(alice);
        vm.roll(blockNumber);
        vm.expectEmit(true, true, true, true);
        emit IContinuousClearingAuction.TokensClaimed(bidId, alice, bid.tokensFilled);
        auction.claimTokens(bidId);

        assertLe(ERC20Mock(mParams.token).balanceOf(alice), aliceTokensBefore + bid.tokensFilled, 'tokens filled');
    }

    modifier givenGraduated() {
        _;
    }

    function test_WhenTokensFilledIsZero(AuctionFuzzConstructorParams memory _params, uint256 _blockNumber)
        external
        givenPastClaimBlock
        givenGraduated
    {
        // it does not emit {TokensClaimed}
        // it does not transfer tokens

        alice = makeAddr('alice');

        AuctionFuzzConstructorParams memory mParams = validAuctionConstructorInputs(_params);
        mParams.token = address(new ERC20Mock());
        mParams.parameters.currency = address(0);
        mParams.parameters.validationHook = address(0);
        // No currency raised required
        mParams.parameters.requiredCurrencyRaised = 0;
        mParams.parameters.fundsRecipient = makeAddr('fundsRecipient');
        mParams.parameters.tokensRecipient = makeAddr('tokensRecipient');
        mParams.parameters.tickSpacing = bound(mParams.parameters.tickSpacing, 2, type(uint24).max) * FixedPoint96.Q96;
        mParams.parameters.floorPrice = bound(mParams.parameters.floorPrice, 1, 100) * mParams.parameters.tickSpacing;
        MockContinuousClearingAuction auction =
            new MockContinuousClearingAuction(mParams.token, mParams.totalSupply, mParams.parameters);

        ERC20Mock(mParams.token).mint(address(auction), mParams.totalSupply);
        auction.onTokensReceived();

        uint256 maxPrice = mParams.parameters.floorPrice + mParams.parameters.tickSpacing;

        vm.roll(auction.startBlock());
        uint256 bidId = auction.submitBid{value: 1}(maxPrice, 1, alice, bytes(''));

        vm.roll(auction.endBlock());
        auction.exitBid(bidId);

        assertTrue(auction.isGraduated(), 'Auction must be graduated');

        uint256 blockNumber = bound(_blockNumber, mParams.parameters.claimBlock, type(uint64).max);

        vm.roll(blockNumber);
        // Expect 0 calls to transfer
        vm.expectCall(mParams.token, abi.encodeWithSelector(IERC20Minimal.transfer.selector, address(alice), 0), 0);
        auction.claimTokens(bidId);
    }
}
