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

contract ClaimTokensBatchTest is BttBase {
    function test_WhenBlockIsLTClaimBlock(AuctionFuzzConstructorParams memory _params, uint64 _blockNumber) public {
        // it reverts with NotClaimable

        AuctionFuzzConstructorParams memory mParams = validAuctionConstructorInputs(_params);
        mParams.token = address(new ERC20Mock());
        MockContinuousClearingAuction auction =
            new MockContinuousClearingAuction(mParams.token, mParams.totalSupply, mParams.parameters);

        ERC20Mock(mParams.token).mint(address(auction), mParams.totalSupply);
        auction.onTokensReceived();

        _blockNumber = uint64(bound(_blockNumber, 0, mParams.parameters.claimBlock - 1));
        vm.roll(_blockNumber);
        vm.expectRevert(IContinuousClearingAuction.NotClaimable.selector);
        auction.claimTokensBatch(address(0), new uint256[](0));
    }

    modifier givenPastClaimBlock() {
        _;
    }

    function test_WhenLastCheckpointedBlockIsNotTheEndBlock(
        AuctionFuzzConstructorParams memory _params,
        uint64 _blockNumber,
        uint128 _bidAmount
    ) public givenPastClaimBlock {
        // it checkpoints the auction
        // it claims the tokens for the bids

        vm.deal(address(this), type(uint256).max);
        vm.assume(_bidAmount > 0);

        AuctionFuzzConstructorParams memory mParams = validAuctionConstructorInputs(_params);
        mParams.token = address(new ERC20Mock());
        mParams.parameters.currency = address(0);
        mParams.parameters.validationHook = address(0);
        vm.assume(mParams.parameters.endBlock > mParams.parameters.startBlock + 1);
        vm.assume(
            mParams.parameters.floorPrice + mParams.parameters.tickSpacing * 2
                < MaxBidPriceLib.maxBidPrice(mParams.totalSupply)
        );
        // Make it graduated by default
        mParams.parameters.requiredCurrencyRaised = 0;
        MockContinuousClearingAuction auction =
            new MockContinuousClearingAuction(mParams.token, mParams.totalSupply, mParams.parameters);

        ERC20Mock(mParams.token).mint(address(auction), mParams.totalSupply);
        auction.onTokensReceived();

        vm.roll(mParams.parameters.startBlock);

        address owner = makeAddr('owner');

        uint256 maxPrice = mParams.parameters.floorPrice + mParams.parameters.tickSpacing;
        uint256 bidId = auction.submitBid{value: _bidAmount}(maxPrice, _bidAmount, owner, bytes(''));

        // Add a bid higher than the first
        maxPrice = maxPrice + mParams.parameters.tickSpacing;
        // Sell out the auction at that price
        uint128 amount = uint128(FixedPointMathLib.fullMulDivUp(mParams.totalSupply, maxPrice, FixedPoint96.Q96));
        vm.assume(amount > 0);
        auction.submitBid{value: amount}(maxPrice, amount, owner, bytes(''));

        vm.roll(mParams.parameters.endBlock - 1);
        // Exit the first bid which is outbid
        auction.exitPartiallyFilledBid(bidId, mParams.parameters.startBlock, mParams.parameters.endBlock - 1);

        _blockNumber = uint64(bound(_blockNumber, mParams.parameters.claimBlock, type(uint64).max));

        uint256[] memory bidIds = new uint256[](1);
        bidIds[0] = bidId;

        vm.roll(_blockNumber);
        assertNotEq(
            auction.lastCheckpointedBlock(),
            mParams.parameters.endBlock,
            'Last checkpointed block should not be the end block'
        );
        vm.expectEmit(true, true, true, true);
        emit IContinuousClearingAuction.CheckpointUpdated(mParams.parameters.endBlock, maxPrice, ConstantsLib.MPS);
        auction.claimTokensBatch(owner, bidIds);
    }

    modifier givenEndBlockIsCheckpointed() {
        _;
    }

    function test_WhenAuctionIsNotGraduated_reverts(
        AuctionFuzzConstructorParams memory _params,
        uint64 _blockNumber,
        uint128 _bidAmount
    ) public givenEndBlockIsCheckpointed {
        // it reverts with NotGraduated

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

        _blockNumber = uint64(bound(_blockNumber, mParams.parameters.claimBlock, type(uint64).max));

        uint256[] memory bidIds = new uint256[](1);
        bidIds[0] = bidId;

        vm.roll(_blockNumber);
        vm.expectRevert(ITokenCurrencyStorage.NotGraduated.selector);
        auction.claimTokensBatch(owner, bidIds);
    }

    modifier givenAuctionIsGraduated() {
        _;
    }

    function test_WhenBatchClaimDifferentOwner_reverts(
        AuctionFuzzConstructorParams memory _params,
        uint64 _blockNumber,
        uint128 _bidAmount
    ) public givenAuctionIsGraduated {
        // it reverts with BatchClaimDifferentOwner

        vm.deal(address(this), type(uint256).max);
        vm.assume(_bidAmount > 0);

        AuctionFuzzConstructorParams memory mParams = validAuctionConstructorInputs(_params);
        mParams.token = address(new ERC20Mock());
        mParams.parameters.currency = address(0);
        mParams.parameters.validationHook = address(0);
        mParams.parameters.requiredCurrencyRaised = 0;

        MockContinuousClearingAuction auction =
            new MockContinuousClearingAuction(mParams.token, mParams.totalSupply, mParams.parameters);

        ERC20Mock(mParams.token).mint(address(auction), mParams.totalSupply);
        auction.onTokensReceived();

        vm.roll(mParams.parameters.startBlock);

        address owner = makeAddr('owner');
        address owner2 = makeAddr('owner2');

        uint256 maxPrice = mParams.parameters.floorPrice + mParams.parameters.tickSpacing;
        uint256 bidId = auction.submitBid{value: _bidAmount}(maxPrice, _bidAmount, owner, bytes(''));
        // Submit identical bid to the first bid but to a different owner
        uint256 bidId2 = auction.submitBid{value: _bidAmount}(maxPrice, _bidAmount, owner2, bytes(''));

        vm.roll(mParams.parameters.endBlock);
        Checkpoint memory checkpoint = auction.checkpoint();
        if (checkpoint.clearingPrice < maxPrice) {
            auction.exitBid(bidId);
            auction.exitBid(bidId2);
        } else {
            auction.exitPartiallyFilledBid(bidId, mParams.parameters.startBlock, 0);
            auction.exitPartiallyFilledBid(bidId2, mParams.parameters.startBlock, 0);
        }

        _blockNumber = uint64(bound(_blockNumber, mParams.parameters.claimBlock, type(uint64).max));

        uint256[] memory bidIds = new uint256[](2);
        bidIds[0] = bidId;
        bidIds[1] = bidId2;

        vm.roll(_blockNumber);
        vm.expectRevert(
            abi.encodeWithSelector(IContinuousClearingAuction.BatchClaimDifferentOwner.selector, owner, owner2)
        );
        // Try to claim the tokens for the bids for the first owner
        auction.claimTokensBatch(owner, bidIds);
    }
}
