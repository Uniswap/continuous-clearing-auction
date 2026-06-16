// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import {AuctionFuzzConstructorParams, BttBase} from '../BttBase.sol';
import {MockContinuousClearingAuction} from '../mocks/MockContinuousClearingAuction.sol';
import {ERC20Mock} from 'openzeppelin-contracts/contracts/mocks/token/ERC20Mock.sol';
import {FixedPointMathLib} from 'solady/utils/FixedPointMathLib.sol';
import {Bid} from 'src/BidStorage.sol';
import {Checkpoint} from 'src/CheckpointStorage.sol';
import {IContinuousClearingAuction} from 'src/interfaces/IContinuousClearingAuction.sol';
import {CheckpointAccountingLib} from 'src/libraries/CheckpointAccountingLib.sol';
import {ConstantsLib} from 'src/libraries/ConstantsLib.sol';
import {FixedPoint96} from 'src/libraries/FixedPoint96.sol';
import {MaxBidPriceLib} from 'src/libraries/MaxBidPriceLib.sol';
import {ValueX7} from 'src/libraries/ValueX7Lib.sol';

contract CheckpointTest is BttBase {
    function _totalSupplyQ96X7(MockContinuousClearingAuction _auction) internal view returns (ValueX7) {
        return ValueX7.wrap(uint256(_auction.totalSupply()) * FixedPoint96.Q96 * ConstantsLib.MPS);
    }

    function test_WhenAuctionIsNotActive(AuctionFuzzConstructorParams memory _params) public {
        // it reverts with {AuctionNotStarted}

        AuctionFuzzConstructorParams memory mParams = validAuctionConstructorInputs(_params);
        mParams.token = address(new ERC20Mock());

        MockContinuousClearingAuction auction =
            new MockContinuousClearingAuction(mParams.token, mParams.totalSupply, mParams.parameters, address(0));

        ERC20Mock(mParams.token).mint(address(auction), requiredTokenDeposit(mParams));
        auction.onTokensReceived();

        vm.roll(mParams.parameters.startBlock - 1);
        vm.expectRevert(IContinuousClearingAuction.AuctionNotStarted.selector);
        auction.checkpoint();
    }

    modifier givenAuctionIsActive() {
        _;
    }

    function test_WhenBlockNumberGTEndBlock(AuctionFuzzConstructorParams memory _params, uint64 _blockNumber)
        public
        givenAuctionIsActive
    {
        // it returns the final checkpoint

        AuctionFuzzConstructorParams memory mParams = validAuctionConstructorInputs(_params);
        mParams.token = address(new ERC20Mock());
        _blockNumber = uint64(bound(_blockNumber, mParams.parameters.endBlock + 1, type(uint64).max));

        MockContinuousClearingAuction auction =
            new MockContinuousClearingAuction(mParams.token, mParams.totalSupply, mParams.parameters, address(0));

        ERC20Mock(mParams.token).mint(address(auction), requiredTokenDeposit(mParams));
        auction.onTokensReceived();

        vm.roll(_blockNumber);
        Checkpoint memory checkpoint = auction.checkpoint();
        assertEq(checkpoint.cumulativeMps, ConstantsLib.MPS);
    }

    function test_WhenBlockNumberLTEndBlock(AuctionFuzzConstructorParams memory _params) public givenAuctionIsActive {
        // it returns the checkpoint at the block number

        AuctionFuzzConstructorParams memory mParams = validAuctionConstructorInputs(_params);
        mParams.token = address(new ERC20Mock());

        MockContinuousClearingAuction auction =
            new MockContinuousClearingAuction(mParams.token, mParams.totalSupply, mParams.parameters, address(0));

        ERC20Mock(mParams.token).mint(address(auction), requiredTokenDeposit(mParams));
        auction.onTokensReceived();

        vm.roll(mParams.parameters.startBlock);
        Checkpoint memory checkpoint = auction.checkpoint();
        assertEq(checkpoint.cumulativeMps, 0);
    }

    function test_WhenBlockNumberIsSameAsLastCheckpointedBlock(AuctionFuzzConstructorParams memory _params)
        public
        givenAuctionIsActive
    {
        // it does not create a new checkpoint

        AuctionFuzzConstructorParams memory mParams = validAuctionConstructorInputs(_params);
        mParams.token = address(new ERC20Mock());

        MockContinuousClearingAuction auction =
            new MockContinuousClearingAuction(mParams.token, mParams.totalSupply, mParams.parameters, address(0));

        ERC20Mock(mParams.token).mint(address(auction), requiredTokenDeposit(mParams));
        auction.onTokensReceived();

        vm.roll(mParams.parameters.startBlock);
        Checkpoint memory checkpoint = auction.checkpoint();

        vm.record();
        Checkpoint memory checkpoint2 = auction.checkpoint();

        if (!isCoverage()) {
            // Should not write to storage
            (, bytes32[] memory writes) = vm.accesses(address(auction));
            assertEq(writes.length, 0);
        }

        assertEq(checkpoint, checkpoint2);
    }

    function test_WhenRemainingSupplyIsZero_DoesNotUpdateAccounting(AuctionFuzzConstructorParams memory _params)
        public
        givenAuctionIsActive
    {
        // it does not update totalClearedQ96X7 or currencyRaisedQ96X7
        // it still advances cumulativeMps

        AuctionFuzzConstructorParams memory mParams = validAuctionConstructorInputs(_params);
        mParams.token = address(new ERC20Mock());
        mParams.parameters.currency = address(0);
        mParams.parameters.validationHook = address(0);

        MockContinuousClearingAuction auction =
            new MockContinuousClearingAuction(mParams.token, mParams.totalSupply, mParams.parameters, address(0));
        ERC20Mock(mParams.token).mint(address(auction), requiredTokenDeposit(mParams));
        auction.onTokensReceived();

        vm.roll(mParams.parameters.startBlock);
        vm.deal(address(this), type(uint256).max);
        uint256 bidPrice = mParams.parameters.floorPrice + mParams.parameters.tickSpacing;
        vm.assume(bidPrice <= MaxBidPriceLib.maxBidPrice(mParams.totalSupply));
        uint128 bidAmount = uint128(FixedPointMathLib.fullMulDivUp(mParams.totalSupply, bidPrice, FixedPoint96.Q96));
        vm.assume(bidAmount > 0);
        auction.submitBid{value: bidAmount}(bidPrice, bidAmount, address(this), bytes(''));

        // Create an initial checkpoint so there is some cumulativeMps
        vm.roll(mParams.parameters.startBlock + 1);
        auction.checkpoint();
        Checkpoint memory cpBefore = auction.latestCheckpoint();

        // Force remainingSupplyQ96X7 to zero
        auction.uncheckedSetTotalCleared(_totalSupplyQ96X7(auction));
        assertEq(ValueX7.unwrap(auction.remainingSupplyQ96X7()), 0);

        ValueX7 totalClearedBefore = auction.totalClearedQ96X7();
        ValueX7 currencyRaisedBefore = auction.currencyRaisedQ96X7();

        // Roll to end block to guarantee deltaMps > 0 (remaining schedule must be consumed)
        vm.roll(mParams.parameters.endBlock + 1);
        Checkpoint memory cpAfter = auction.checkpoint();

        // Accounting should not change
        assertEq(ValueX7.unwrap(auction.totalClearedQ96X7()), ValueX7.unwrap(totalClearedBefore));
        assertEq(ValueX7.unwrap(auction.currencyRaisedQ96X7()), ValueX7.unwrap(currencyRaisedBefore));
        assertEq(cpAfter.cumulativeMpsPerPrice, cpBefore.cumulativeMpsPerPrice);

        // cumulativeMps must reach MPS
        assertEq(cpAfter.cumulativeMps, ConstantsLib.MPS);
    }

    /// forge-config: default.fuzz.runs = 888
    function test_WhenSupplyExhausted_BidReceivesNoMoreTokensButSpendsMoreCurrency(
        AuctionFuzzConstructorParams memory _params,
        uint8 _n
    ) public givenAuctionIsActive {
        // it does not award additional tokens after supply runs out
        // it increases currency spent because the auction schedule still advances

        vm.assume(_n > 0 && _n < 5);
        vm.deal(address(this), type(uint256).max);

        AuctionFuzzConstructorParams memory mParams = validAuctionConstructorInputs(_params);
        mParams.token = address(new ERC20Mock());
        mParams.parameters.currency = address(0);
        mParams.parameters.validationHook = address(0);
        vm.assume(mParams.parameters.startBlock + uint256(_n) + 2 < mParams.parameters.endBlock);
        uint256 maxBidPrice = MaxBidPriceLib.maxBidPrice(mParams.totalSupply);
        vm.assume(mParams.parameters.floorPrice + mParams.parameters.tickSpacing * _n < maxBidPrice);

        MockContinuousClearingAuction auction =
            new MockContinuousClearingAuction(mParams.token, mParams.totalSupply, mParams.parameters, address(0));
        ERC20Mock(mParams.token).mint(address(auction), requiredTokenDeposit(mParams));
        auction.onTokensReceived();

        vm.roll(mParams.parameters.startBlock);

        // Submit N small bids at ascending ticks
        for (uint8 i = 1; i <= _n; i++) {
            uint256 price = mParams.parameters.floorPrice + uint256(i) * mParams.parameters.tickSpacing;
            if (price > maxBidPrice) break;
            auction.submitBid{value: 1}(price, 1, address(this), bytes(''));
        }

        // Submit a large bid that will be used to measure fill changes
        uint256 topPrice = mParams.parameters.floorPrice + uint256(_n) * mParams.parameters.tickSpacing;
        uint128 largeAmount = uint128(FixedPointMathLib.fullMulDivUp(mParams.totalSupply, topPrice, FixedPoint96.Q96));
        vm.assume(largeAmount > 0);
        auction.submitBid{value: largeAmount}(topPrice, largeAmount, address(this), bytes(''));

        // Advance a few blocks so some tokens clear normally
        vm.roll(mParams.parameters.startBlock + _n);
        auction.checkpoint();
        Checkpoint memory cpAtExhaustion = auction.latestCheckpoint();

        // Force supply exhaustion (simulates rounding overshoot)
        auction.uncheckedSetTotalCleared(_totalSupplyQ96X7(auction));

        // Run auction to completion
        vm.roll(mParams.parameters.endBlock + 1);
        Checkpoint memory cpFinal = auction.checkpoint();
        assertEq(cpFinal.cumulativeMps, ConstantsLib.MPS);

        // cumulativeMpsPerPrice must not change after exhaustion (no tokens were sold)
        assertEq(cpFinal.cumulativeMpsPerPrice, cpAtExhaustion.cumulativeMpsPerPrice);

        // Construct a representative bid to measure fill
        Bid memory bid = Bid({
            startBlock: uint64(mParams.parameters.startBlock),
            startCumulativeMps: 0,
            exitedBlock: 0,
            maxPrice: topPrice,
            owner: address(this),
            amountQ96: uint256(largeAmount) * FixedPoint96.Q96,
            tokensFilled: 0
        });

        // Fill at exhaustion checkpoint vs. at the start
        (uint256 tokensAtExhaustion, uint256 currencyAtExhaustion) = CheckpointAccountingLib.calculateFill(
            bid, cpAtExhaustion.cumulativeMpsPerPrice, cpAtExhaustion.cumulativeMps
        );

        // Fill at final checkpoint vs. at the start
        (uint256 tokensAtEnd, uint256 currencyAtEnd) =
            CheckpointAccountingLib.calculateFill(bid, cpFinal.cumulativeMpsPerPrice, cpFinal.cumulativeMps);

        // Tokens received must not increase after supply is exhausted
        assertEq(tokensAtEnd, tokensAtExhaustion, 'tokens should not increase after supply exhaustion');

        // Currency spent must increase because the auction schedule continued
        // (cumulativeMps advanced while cumulativeMpsPerPrice stayed flat)
        assertGt(currencyAtEnd, currencyAtExhaustion, 'currency spent should increase');
    }
}
