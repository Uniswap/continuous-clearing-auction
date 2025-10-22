// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Auction, AuctionParameters} from '../src/Auction.sol';
import {Bid} from '../src/BidStorage.sol';
import {Checkpoint} from '../src/CheckpointStorage.sol';
import {IAuction} from '../src/interfaces/IAuction.sol';
import {IAuctionStepStorage} from '../src/interfaces/IAuctionStepStorage.sol';
import {ITickStorage} from '../src/interfaces/ITickStorage.sol';
import {ITokenCurrencyStorage} from '../src/interfaces/ITokenCurrencyStorage.sol';
import {AuctionStep} from '../src/libraries/AuctionStepLib.sol';
import {AuctionStepLib} from '../src/libraries/AuctionStepLib.sol';
import {BidLib} from '../src/libraries/BidLib.sol';
import {Checkpoint} from '../src/libraries/CheckpointLib.sol';
import {CheckpointLib} from '../src/libraries/CheckpointLib.sol';
import {ConstantsLib} from '../src/libraries/ConstantsLib.sol';
import {Currency, CurrencyLibrary} from '../src/libraries/CurrencyLibrary.sol';
import {FixedPoint128} from '../src/libraries/FixedPoint128.sol';
import {FixedPoint96} from '../src/libraries/FixedPoint96.sol';
import {ValueX7, ValueX7Lib} from '../src/libraries/ValueX7Lib.sol';
import {AuctionBaseTest} from './utils/AuctionBaseTest.sol';
import {AuctionParamsBuilder} from './utils/AuctionParamsBuilder.sol';
import {AuctionStepsBuilder} from './utils/AuctionStepsBuilder.sol';
import {FuzzBid, FuzzDeploymentParams} from './utils/FuzzStructs.sol';
import {MockAuction} from './utils/MockAuction.sol';
import {MockFundsRecipient} from './utils/MockFundsRecipient.sol';
import {MockValidationHook} from './utils/MockValidationHook.sol';
import {TickBitmap, TickBitmapLib} from './utils/TickBitmap.sol';
import {TokenHandler} from './utils/TokenHandler.sol';
import {Test} from 'forge-std/Test.sol';
import {console} from 'forge-std/console.sol';
import {console2} from 'forge-std/console2.sol';
import {FixedPointMathLib} from 'solady/utils/FixedPointMathLib.sol';
import {SafeCastLib} from 'solady/utils/SafeCastLib.sol';
import {SafeTransferLib} from 'solady/utils/SafeTransferLib.sol';
import {Checkpoint} from 'src/CheckpointStorage.sol';

contract AuctionTest is AuctionBaseTest {
    using FixedPointMathLib for *;
    using AuctionParamsBuilder for AuctionParameters;
    using AuctionStepsBuilder for bytes;
    using ValueX7Lib for *;
    using BidLib for *;

    function setUp() public {
        setUpAuction();
    }

    function test_submitBid_beforeTokensReceived_reverts() public {
        Auction newAuction = new Auction(address(token), TOTAL_SUPPLY, params);
        token.mint(address(newAuction), TOTAL_SUPPLY);
        vm.expectRevert(IAuction.TokensNotReceived.selector);
        // Submit random bid, will revert
        newAuction.submitBid{value: inputAmountForTokens(100e18, tickNumberToPriceX96(2))}(
            tickNumberToPriceX96(2),
            inputAmountForTokens(100e18, tickNumberToPriceX96(2)),
            alice,
            tickNumberToPriceX96(1),
            bytes('')
        );
    }

    function test_checkpoint_beforeTokensReceived_reverts() public {
        Auction newAuction = new Auction(address(token), TOTAL_SUPPLY, params);
        token.mint(address(newAuction), TOTAL_SUPPLY);
        vm.expectRevert(IAuction.TokensNotReceived.selector);
        newAuction.checkpoint();
    }

    /// forge-config: default.isolate = true
    /// forge-config: ci.isolate = true
    function test_submitBid_exactIn_succeeds_gas() public {
        vm.expectEmit(true, true, true, true);
        emit IAuction.BidSubmitted(
            0, alice, tickNumberToPriceX96(2), inputAmountForTokens(100e18, tickNumberToPriceX96(2))
        );
        auction.submitBid{value: inputAmountForTokens(100e18, tickNumberToPriceX96(2))}(
            tickNumberToPriceX96(2),
            inputAmountForTokens(100e18, tickNumberToPriceX96(2)),
            alice,
            tickNumberToPriceX96(1),
            bytes('')
        );
        vm.snapshotGasLastCall('submitBid_recordStep_updateCheckpoint');

        vm.roll(block.number + 1);
        auction.submitBid{value: inputAmountForTokens(100e18, tickNumberToPriceX96(2))}(
            tickNumberToPriceX96(2),
            inputAmountForTokens(100e18, tickNumberToPriceX96(2)),
            alice,
            tickNumberToPriceX96(1),
            bytes('')
        );
        vm.snapshotGasLastCall('submitBid_updateCheckpoint');

        auction.submitBid{value: inputAmountForTokens(100e18, tickNumberToPriceX96(2))}(
            tickNumberToPriceX96(2),
            inputAmountForTokens(100e18, tickNumberToPriceX96(2)),
            alice,
            tickNumberToPriceX96(1),
            bytes('')
        );
        vm.snapshotGasLastCall('submitBid');
    }

    /// forge-config: default.isolate = true
    /// forge-config: ci.isolate = true
    function test_submitBid_exactIn_initializesTickAndUpdatesClearingPrice_succeeds_gas() public {
        vm.expectEmit(true, true, true, true);
        emit IAuction.BidSubmitted(
            0, alice, tickNumberToPriceX96(2), inputAmountForTokens(TOTAL_SUPPLY, tickNumberToPriceX96(2))
        );
        auction.submitBid{value: inputAmountForTokens(TOTAL_SUPPLY, tickNumberToPriceX96(2))}(
            tickNumberToPriceX96(2),
            inputAmountForTokens(TOTAL_SUPPLY, tickNumberToPriceX96(2)),
            alice,
            tickNumberToPriceX96(1),
            bytes('')
        );
        vm.snapshotGasLastCall('submitBid_recordStep_updateCheckpoint_initializeTick');

        vm.roll(block.number + 1);
        uint24 expectedCumulativeMps = 100e3; // 100e3 mps * 1 block
        ValueX7 expectedTotalCurrencyRaised = ValueX7.wrap(TOTAL_SUPPLY_Q96)
            .wrapAndFullMulDiv(tickNumberToPriceX96(2) * expectedCumulativeMps, FixedPoint96.Q96);
        vm.expectEmit(true, true, true, true);
        emit IAuction.CheckpointUpdated(
            block.number, tickNumberToPriceX96(2), expectedTotalCurrencyRaised, expectedCumulativeMps
        );
        auction.checkpoint();

        assertEq(auction.clearingPrice(), tickNumberToPriceX96(2));
    }

    function test_submitBid_updatesClearingPrice_succeeds() public {
        vm.expectEmit(true, true, true, true);
        // Expect the checkpoint to be made for the previous block
        emit IAuction.CheckpointUpdated(block.number, tickNumberToPriceX96(1), ValueX7.wrap(0), 0);
        // Bid enough to purchase the entire supply (1000e18) at a higher price (2e18)
        uint128 inputAmount = inputAmountForTokens(TOTAL_SUPPLY, tickNumberToPriceX96(2));
        auction.submitBid{value: inputAmount}(
            tickNumberToPriceX96(2), inputAmount, alice, tickNumberToPriceX96(1), bytes('')
        );

        vm.roll(block.number + 1);
        uint24 expectedCumulativeMps = 100e3; // 100e3 mps * 1 block
        ValueX7 expectedCurrencyRaised = ValueX7.wrap(TOTAL_SUPPLY_Q96)
            .wrapAndFullMulDiv(tickNumberToPriceX96(2) * expectedCumulativeMps, FixedPoint96.Q96);
        vm.expectEmit(true, true, true, true);
        emit IAuction.CheckpointUpdated(
            block.number, tickNumberToPriceX96(2), expectedCurrencyRaised, expectedCumulativeMps
        );
        auction.checkpoint();
    }

    function test_submitBid_multipleTicks_succeeds() public {
        vm.expectEmit(true, true, true, true);
        // First checkpoint is blank
        emit IAuction.CheckpointUpdated(block.number, tickNumberToPriceX96(1), ValueX7.wrap(0), 0);
        vm.expectEmit(true, true, true, true);
        emit ITickStorage.TickInitialized(tickNumberToPriceX96(2));

        // Bid to purchase 500e18 tokens at a price of 2e6
        auction.submitBid{value: inputAmountForTokens(500e18, tickNumberToPriceX96(2))}(
            tickNumberToPriceX96(2),
            inputAmountForTokens(500e18, tickNumberToPriceX96(2)),
            alice,
            tickNumberToPriceX96(1),
            bytes('')
        );

        vm.expectEmit(true, true, true, true);
        emit ITickStorage.TickInitialized(tickNumberToPriceX96(3));
        // Bid 1503 ETH to purchase 501 tokens at a price of 3
        // This bid will move the clearing price because now demand > total supply but no checkpoint is made until the next block
        auction.submitBid{value: inputAmountForTokens(501e18, tickNumberToPriceX96(3))}(
            tickNumberToPriceX96(3),
            inputAmountForTokens(501e18, tickNumberToPriceX96(3)),
            alice,
            tickNumberToPriceX96(2),
            bytes('')
        );

        vm.roll(block.number + 1);
        uint24 expectedCumulativeMps = 100e3; // 100e3 mps * 1 block
        ValueX7 expectedCurrencyRaised = ValueX7.wrap(TOTAL_SUPPLY_Q96)
            .wrapAndFullMulDiv(tickNumberToPriceX96(2) * expectedCumulativeMps, FixedPoint96.Q96);
        // New block, expect the clearing price to be updated and one block's worth of mps to be sold
        vm.expectEmit(true, true, true, true);
        emit IAuction.CheckpointUpdated(
            block.number, tickNumberToPriceX96(2), expectedCurrencyRaised, expectedCumulativeMps
        );
        auction.checkpoint();
    }

    function test_submitBid_exactIn_overTotalSupply_isPartiallyFilled() public {
        uint128 inputAmount = inputAmountForTokens(2000e18, tickNumberToPriceX96(2));
        uint256 bidId = auction.submitBid{value: inputAmount}(
            tickNumberToPriceX96(2), inputAmount, alice, tickNumberToPriceX96(1), bytes('')
        );

        vm.roll(block.number + 1);
        auction.checkpoint();

        vm.roll(auction.endBlock());
        uint256 aliceBalanceBefore = address(alice).balance;
        uint256 aliceTokenBalanceBefore = token.balanceOf(address(alice));

        auction.exitPartiallyFilledBid(bidId, 1, 0);
        assertEq(address(alice).balance, aliceBalanceBefore + inputAmount / 2);

        vm.roll(auction.claimBlock());
        vm.expectEmit(true, true, true, true);
        emit IAuction.TokensClaimed(bidId, alice, 1000e18);
        auction.claimTokens(bidId);
        assertEq(token.balanceOf(address(alice)), aliceTokenBalanceBefore + 1000e18);
    }

    /// forge-config: default.isolate = true
    /// forge-config: ci.isolate = true
    function test_submitBid_zeroSupply_exitPartiallyFilledBid_succeeds_gas() public {
        // 0 mps for first 50 blocks, then 200mps for the last 50 blocks
        params = params.withAuctionStepsData(AuctionStepsBuilder.init().addStep(0, 100).addStep(100e3, 100))
            .withEndBlock(block.number + 200).withClaimBlock(block.number + 200);
        auction = new Auction(address(token), TOTAL_SUPPLY, params);
        token.mint(address(auction), TOTAL_SUPPLY);
        auction.onTokensReceived();

        // Bid over the total supply
        uint128 inputAmount = inputAmountForTokens(2000e18, tickNumberToPriceX96(2));
        vm.expectEmit(true, true, true, true);
        emit IAuction.CheckpointUpdated(block.number, tickNumberToPriceX96(1), ValueX7.wrap(0), 0);
        vm.expectEmit(true, true, true, true);
        emit IAuction.BidSubmitted(0, alice, tickNumberToPriceX96(2), inputAmount);
        uint256 bidId = auction.submitBid{value: inputAmount}(
            tickNumberToPriceX96(2), inputAmount, alice, tickNumberToPriceX96(1), bytes('')
        );

        // Advance to the next block to get the next checkpoint
        vm.roll(block.number + 1);
        vm.expectEmit(true, true, true, true);
        // Expect the price to increase, but no tokens to be sold
        emit IAuction.CheckpointUpdated(block.number, tickNumberToPriceX96(2), ValueX7.wrap(0), 0);
        auction.checkpoint();
        vm.snapshotGasLastCall('checkpoint_zeroSupply');

        // Advance to the end of the first step
        vm.roll(auction.startBlock() + 101);

        uint24 expectedCumulativeMps = 100e3; // 100e3 mps * 1 block
        ValueX7 expectedTotalCurrencyRaised = ValueX7.wrap(TOTAL_SUPPLY_Q96)
            .wrapAndFullMulDiv(tickNumberToPriceX96(2) * expectedCumulativeMps, FixedPoint96.Q96);
        // Now the auction should start clearing
        vm.expectEmit(true, true, true, true);
        emit IAuction.CheckpointUpdated(
            block.number, tickNumberToPriceX96(2), expectedTotalCurrencyRaised, expectedCumulativeMps
        );
        auction.checkpoint();

        vm.roll(auction.endBlock());
        uint256 aliceBalanceBefore = address(alice).balance;
        uint256 aliceTokenBalanceBefore = token.balanceOf(address(alice));

        auction.exitPartiallyFilledBid(bidId, 1, 0);
        assertEq(address(alice).balance, aliceBalanceBefore + inputAmount / 2);

        vm.roll(auction.claimBlock());
        vm.expectEmit(true, true, true, true);
        emit IAuction.TokensClaimed(bidId, alice, 1000e18);
        auction.claimTokens(bidId);
        assertEq(token.balanceOf(address(alice)), aliceTokenBalanceBefore + 1000e18);
    }

    function test_submitBid_zeroSupply_exitBid_succeeds(uint128 _bidAmount, uint128 _maxPrice)
        public
        givenValidMaxPrice(_maxPrice, TOTAL_SUPPLY)
        givenValidBidAmount(_bidAmount)
        givenGraduatedAuction
        givenFullyFundedAccount
        checkAuctionIsGraduated
        checkAuctionIsSolvent
    {
        // 0 mps for first 50 blocks, then 200mps for the last 50 blocks
        params = params.withAuctionStepsData(AuctionStepsBuilder.init().addStep(0, 100).addStep(100e3, 100))
            .withEndBlock(block.number + 200).withClaimBlock(block.number + 200);
        auction = new Auction(address(token), TOTAL_SUPPLY, params);
        token.mint(address(auction), TOTAL_SUPPLY);
        auction.onTokensReceived();

        vm.expectEmit(true, true, true, true);
        emit IAuction.CheckpointUpdated(block.number, FLOOR_PRICE, ValueX7.wrap(0), 0);
        vm.expectEmit(true, true, true, true);
        emit IAuction.BidSubmitted(0, alice, $maxPrice, $bidAmount);
        uint256 bidId = auction.submitBid{value: $bidAmount}($maxPrice, $bidAmount, alice, FLOOR_PRICE, bytes(''));

        // Advance to the next block to get the next checkpoint
        vm.roll(block.number + 1);
        auction.checkpoint();

        // Advance to the end of the first step
        vm.roll(auction.startBlock() + 101);

        // Now the auction should start clearing
        Checkpoint memory checkpoint = auction.checkpoint();
        assertEq(checkpoint.cumulativeMps, 100e3);

        vm.roll(auction.endBlock());
        uint256 aliceBalanceBefore = address(alice).balance;

        if ($maxPrice > checkpoint.clearingPrice) {
            auction.exitBid(bidId);
        } else {
            auction.exitPartiallyFilledBid(bidId, 1, 0);
        }
        // Alice will have received a refund if the bid was higher than the total supply
        assertGe(address(alice).balance, aliceBalanceBefore);

        vm.roll(auction.claimBlock());
        uint256 expectedTokensFilled = auction.bids(bidId).tokensFilled;
        vm.assume(expectedTokensFilled > 0);

        vm.expectEmit(true, true, true, true);
        emit IAuction.TokensClaimed(bidId, alice, expectedTokensFilled);
        auction.claimTokens(bidId);
        assertEq(token.balanceOf(address(alice)), expectedTokensFilled);
    }

    function test_submitBid_noRolloverSupply(uint128 _bidAmount, uint256 _maxPrice, uint256 _seed)
        public
        givenValidMaxPrice(_maxPrice, TOTAL_SUPPLY)
        givenValidBidAmount(_bidAmount)
        givenGraduatedAuction
        givenFullyFundedAccount
        checkAuctionIsGraduated
        checkAuctionIsSolvent
    {
        // Advance by one such that the auction is already started
        uint256 targetBlock =
            _bound(_seed % (auction.endBlock() - auction.startBlock()), block.number + 1, auction.endBlock());

        vm.roll(targetBlock);
        uint256 bidId =
            auction.submitBid{value: $bidAmount}($maxPrice, $bidAmount, alice, tickNumberToPriceX96(1), bytes(''));

        vm.roll(auction.endBlock());
        Checkpoint memory checkpoint = auction.checkpoint();
        if ($maxPrice > checkpoint.clearingPrice) {
            auction.exitBid(bidId);
        } else {
            auction.exitPartiallyFilledBid(bidId, uint64(targetBlock), 0);
        }

        uint256 expectedTokensFilled = auction.bids(bidId).tokensFilled;
        vm.assume(expectedTokensFilled > 0);

        vm.roll(auction.claimBlock());
        vm.expectEmit(true, true, true, true);
        emit IAuction.TokensClaimed(bidId, alice, expectedTokensFilled);
        auction.claimTokens(bidId);
        assertEq(token.balanceOf(address(alice)), expectedTokensFilled);
    }

    /// forge-config: default.isolate = true
    /// forge-config: ci.isolate = true
    function test_submitBid_withoutPrevTickPrice_isInitialized_succeeds_gas() public {
        vm.expectEmit(true, true, true, true);
        emit ITickStorage.TickInitialized(tickNumberToPriceX96(2));
        auction.submitBid{value: inputAmountForTokens(100e18, tickNumberToPriceX96(2))}(
            tickNumberToPriceX96(2), inputAmountForTokens(100e18, tickNumberToPriceX96(2)), alice, bytes('')
        );
        vm.snapshotGasLastCall('submitBidWithoutPrevTickPrice_initializeTick_updateCheckpoint');

        // Submit another bid at the same price, which is now initialized
        auction.submitBid{value: inputAmountForTokens(100e18, tickNumberToPriceX96(2))}(
            tickNumberToPriceX96(2), inputAmountForTokens(100e18, tickNumberToPriceX96(2)), alice, bytes('')
        );
        vm.snapshotGasLastCall('submitBidWithoutPrevTickPrice');

        // Submit a bid at a higher price which is not initialized, requiring the protocol to search
        auction.submitBid{value: inputAmountForTokens(100e18, tickNumberToPriceX96(3))}(
            tickNumberToPriceX96(3), inputAmountForTokens(100e18, tickNumberToPriceX96(3)), alice, bytes('')
        );
        vm.snapshotGasLastCall('submitBidWithoutPrevTickPrice_initializeTick_search');
    }

    function test_checkpoint_startBlock_succeeds() public {
        vm.roll(auction.startBlock());
        auction.checkpoint();
    }

    function test_checkpoint_endBlock_succeeds() public {
        vm.roll(auction.endBlock());
        auction.checkpoint();
    }

    function test_checkpoint_afterEndBlock_succeeds(uint32 blocksAfterEndBlock, uint8 numberOfInvocations) public {
        uint256 blockInFuture = auction.endBlock() + blocksAfterEndBlock;
        vm.roll(blockInFuture);
        for (uint8 i = 0; i < numberOfInvocations; i++) {
            vm.roll(blockInFuture + i);
            auction.checkpoint();

            // Final checkpoint should remain the same as the last block
            assertEq(auction.lastCheckpointedBlock(), auction.endBlock());
        }
    }

    function test_submitBid_beforeAuctionStartBlock_reverts(uint64 startBlock) public {
        // Fuzz start block to account for the endBlock
        vm.assume(startBlock > 0 && startBlock <= type(uint64).max - 2);
        uint256 auctionDuration = 1;
        params = params.withStartBlock(uint256(startBlock)).withEndBlock(uint256(startBlock) + auctionDuration)
            .withClaimBlock(uint256(startBlock) + 2)
            .withAuctionStepsData(AuctionStepsBuilder.init().addStep(1e7, uint40(auctionDuration)));
        auction = new Auction(address(token), TOTAL_SUPPLY, params);
        token.mint(address(auction), TOTAL_SUPPLY);
        auction.onTokensReceived();

        vm.roll(startBlock - 1);
        vm.expectRevert(IAuction.AuctionNotStarted.selector);
        auction.submitBid{value: inputAmountForTokens(10e18, tickNumberToPriceX96(1))}(
            tickNumberToPriceX96(1), uint128(10e18), alice, tickNumberToPriceX96(1), bytes('')
        );
    }

    function test_submitBid_exactIn_atFloorPrice_reverts() public {
        vm.expectRevert(IAuction.BidMustBeAboveClearingPrice.selector);
        auction.submitBid{value: inputAmountForTokens(10e18, tickNumberToPriceX96(1))}(
            tickNumberToPriceX96(1),
            inputAmountForTokens(10e18, tickNumberToPriceX96(1)),
            alice,
            tickNumberToPriceX96(1),
            bytes('')
        );

        vm.expectRevert(IAuction.BidMustBeAboveClearingPrice.selector);
        auction.submitBid{value: inputAmountForTokens(10e18, tickNumberToPriceX96(1))}(
            tickNumberToPriceX96(1), inputAmountForTokens(10e18, tickNumberToPriceX96(1)), alice, bytes('')
        );
    }

    function test_submitBid_exactInMsgValue_revertsWithInvalidAmount() public {
        vm.expectRevert(IAuction.InvalidAmount.selector);
        // msg.value should be 1000e18
        auction.submitBid{value: 2000e18}(
            tickNumberToPriceX96(2), uint128(1000e18), alice, tickNumberToPriceX96(1), bytes('')
        );

        vm.expectRevert(IAuction.InvalidAmount.selector);
        auction.submitBid{value: 2000e18}(tickNumberToPriceX96(2), uint128(1000e18), alice, bytes(''));
    }

    function test_submitBid_exactInZeroMsgValue_revertsWithInvalidAmount() public {
        vm.expectRevert(IAuction.InvalidAmount.selector);
        auction.submitBid{value: 0}(
            tickNumberToPriceX96(2), uint128(1000e18), alice, tickNumberToPriceX96(1), bytes('')
        );

        vm.expectRevert(IAuction.InvalidAmount.selector);
        auction.submitBid{value: 0}(tickNumberToPriceX96(2), uint128(1000e18), alice, bytes(''));
    }

    function test_submitBid_exactInZeroAmount_revertsWithInvalidAmount() public {
        vm.expectRevert(IAuction.InvalidAmount.selector);
        auction.submitBid{value: 1000e18}(tickNumberToPriceX96(2), 0, alice, tickNumberToPriceX96(1), bytes(''));

        vm.expectRevert(IAuction.InvalidAmount.selector);
        auction.submitBid{value: 1000e18}(tickNumberToPriceX96(2), 0, alice, bytes(''));
    }

    function test_submitBid_endBlock_reverts() public {
        vm.roll(auction.endBlock());
        vm.expectRevert(IAuctionStepStorage.AuctionIsOver.selector);
        auction.submitBid{value: 1000e18}(
            tickNumberToPriceX96(2), uint128(1000e18), alice, tickNumberToPriceX96(1), bytes('')
        );

        vm.expectRevert(IAuctionStepStorage.AuctionIsOver.selector);
        auction.submitBid{value: 1000e18}(tickNumberToPriceX96(2), uint128(1000e18), alice, bytes(''));
    }

    /// forge-config: default.isolate = true
    /// forge-config: ci.isolate = true
    function test_exitBid_succeeds() public {
        uint128 smallAmount = 500e18;
        vm.expectEmit(true, true, true, true);
        emit IAuction.BidSubmitted(
            0, alice, tickNumberToPriceX96(2), inputAmountForTokens(smallAmount, tickNumberToPriceX96(2))
        );
        uint256 bidId1 = auction.submitBid{value: inputAmountForTokens(smallAmount, tickNumberToPriceX96(2))}(
            tickNumberToPriceX96(2),
            inputAmountForTokens(smallAmount, tickNumberToPriceX96(2)),
            alice,
            tickNumberToPriceX96(1),
            bytes('')
        );

        // Bid enough tokens to move the clearing price to 3
        uint128 largeAmount = 1000e18;
        vm.expectEmit(true, true, true, true);
        emit IAuction.BidSubmitted(
            1, alice, tickNumberToPriceX96(3), inputAmountForTokens(largeAmount, tickNumberToPriceX96(3))
        );
        uint256 bidId2 = auction.submitBid{value: inputAmountForTokens(largeAmount, tickNumberToPriceX96(3))}(
            tickNumberToPriceX96(3),
            inputAmountForTokens(largeAmount, tickNumberToPriceX96(3)),
            alice,
            tickNumberToPriceX96(2),
            bytes('')
        );
        uint24 expectedCumulativeMps = 100e3; // 100e3 mps * 1 block
        ValueX7 expectedTotalCurrencyRaised = ValueX7.wrap(TOTAL_SUPPLY_Q96)
            .wrapAndFullMulDiv(tickNumberToPriceX96(3) * expectedCumulativeMps, FixedPoint96.Q96);

        vm.roll(block.number + 1);
        vm.expectEmit(true, true, true, true);
        emit IAuction.CheckpointUpdated(
            block.number, tickNumberToPriceX96(3), expectedTotalCurrencyRaised, expectedCumulativeMps
        );
        auction.checkpoint();

        uint256 aliceBalanceBefore = address(alice).balance;
        // Expect that the first bid can be exited, since the clearing price is now above its max price
        vm.startPrank(alice);
        auction.exitPartiallyFilledBid(bidId1, 1, 2);
        // Expect that alice is refunded the full amount of the first bid
        assertEq(
            address(alice).balance - aliceBalanceBefore, inputAmountForTokens(smallAmount, tickNumberToPriceX96(2))
        );

        // Expect that the second bid cannot be withdrawn, since the clearing price is below its max price
        vm.roll(auction.endBlock());
        vm.expectRevert(IAuction.CannotExitBid.selector);
        auction.exitBid(bidId2);
        vm.stopPrank();

        uint256 expectedCurrencyRaised = inputAmountForTokens(largeAmount, tickNumberToPriceX96(3));
        vm.startPrank(auction.fundsRecipient());
        vm.expectEmit(true, true, true, true);
        emit ITokenCurrencyStorage.CurrencySwept(auction.fundsRecipient(), expectedCurrencyRaised);
        auction.sweepCurrency();
        vm.stopPrank();

        // Auction fully subscribed so no tokens are left
        vm.expectEmit(true, true, true, true);
        emit ITokenCurrencyStorage.TokensSwept(auction.tokensRecipient(), 0);
        auction.sweepUnsoldTokens();
    }

    /// forge-config: default.fuzz.runs = 1000
    /// forge-config: ci.fuzz.runs = 1000
    function test_exitBid_afterEndBlock_succeeds(uint128 _bidAmount, uint128 _maxPrice)
        public
        givenValidMaxPrice(_maxPrice, TOTAL_SUPPLY)
        givenValidBidAmount(_bidAmount)
        givenGraduatedAuction
        givenFullyFundedAccount
    {
        uint256 bidId = auction.submitBid{value: $bidAmount}(
            $maxPrice, $bidAmount, alice, tickNumberToPriceX96(1), bytes('')
        );

        vm.roll(block.number + 1);
        Checkpoint memory checkpoint = auction.checkpoint();

        // Before the auction ends, the bid should not be exitable since it is at the clearing price
        vm.roll(auction.endBlock() - 1);
        if ($maxPrice > checkpoint.clearingPrice) {
            vm.expectRevert(IAuction.AuctionIsNotOver.selector);
            auction.exitBid(bidId);
        } else {
            vm.expectRevert(IAuction.CannotPartiallyExitBidBeforeEndBlock.selector);
            auction.exitPartiallyFilledBid(bidId, 1, 0);
        }

        // Now that the auction has ended, the bid should be exitable
        vm.roll(auction.endBlock());
        if ($maxPrice > checkpoint.clearingPrice) {
            auction.exitBid(bidId);
        } else {
            auction.exitPartiallyFilledBid(bidId, 1, 0);
        }

        vm.roll(auction.claimBlock());
        uint256 expectedTokensFilled = auction.bids(bidId).tokensFilled;
        vm.assume(expectedTokensFilled > 0);

        vm.expectEmit(true, true, true, true);
        emit IAuction.TokensClaimed(bidId, alice, expectedTokensFilled);
        auction.claimTokens(bidId);
        assertEq(token.balanceOf(address(alice)), expectedTokensFilled);
    }

    function test_exitBid_joinedLate_succeeds(uint128 _bidAmount, uint256 _maxPrice)
        public
        givenValidMaxPrice(_maxPrice, TOTAL_SUPPLY)
        givenValidBidAmount(_bidAmount)
        givenGraduatedAuction
        givenFullyFundedAccount
        checkAuctionIsGraduated
        checkAuctionIsSolvent
    {
        vm.roll(auction.endBlock() - 1);
        uint256 bidId1 =
            auction.submitBid{value: $bidAmount}($maxPrice, $bidAmount, alice, tickNumberToPriceX96(1), bytes(''));

        uint256 aliceBalanceBefore = address(alice).balance;

        vm.roll(auction.endBlock());
        Checkpoint memory checkpoint = auction.checkpoint();
        if ($maxPrice > checkpoint.clearingPrice) {
            auction.exitBid(bidId1);
        } else {
            auction.exitPartiallyFilledBid(bidId1, auction.endBlock() - 1, 0);
        }

        vm.roll(auction.claimBlock());
        uint256 expectedTokensFilled = auction.bids(bidId1).tokensFilled;
        vm.assume(expectedTokensFilled > 0);

        vm.expectEmit(true, true, true, true);
        emit IAuction.TokensClaimed(bidId1, alice, expectedTokensFilled);
        auction.claimTokens(bidId1);
        assertEq(token.balanceOf(address(alice)), expectedTokensFilled);
    }

    function test_exitBid_beforeEndBlock_revertsWithCannotExitBid() public {
        uint256 bidId = auction.submitBid{value: inputAmountForTokens(1000e18, tickNumberToPriceX96(3))}(
            tickNumberToPriceX96(3),
            inputAmountForTokens(1000e18, tickNumberToPriceX96(3)),
            alice,
            tickNumberToPriceX96(1),
            bytes('')
        );
        // Expect revert because the bid is not below the clearing price
        vm.roll(auction.endBlock());
        vm.expectRevert(IAuction.CannotExitBid.selector);
        vm.prank(alice);
        auction.exitBid(bidId);
    }

    function test_exitBid_maxPriceAtClearingPrice_revertsWithCannotExitBid() public {
        uint256 bidId = auction.submitBid{value: inputAmountForTokens(1000e18, tickNumberToPriceX96(2))}(
            tickNumberToPriceX96(2),
            inputAmountForTokens(1000e18, tickNumberToPriceX96(2)),
            alice,
            tickNumberToPriceX96(1),
            bytes('')
        );
        vm.roll(block.number + 1);
        auction.checkpoint();
        assertEq(auction.clearingPrice(), tickNumberToPriceX96(2));

        // Auction has ended, but the bid is not exitable through this function because the max price is at the clearing price
        vm.roll(auction.endBlock() + 1);
        vm.expectRevert(IAuction.CannotExitBid.selector);
        vm.prank(alice);
        auction.exitBid(bidId);
    }

    function test_exitBid_revertsWithAlreadyExited(uint128 _bidAmount, uint256 _maxPrice)
        public
        givenValidMaxPrice(_maxPrice, TOTAL_SUPPLY)
        givenValidBidAmount(_bidAmount)
        givenGraduatedAuction
        givenFullyFundedAccount
    {
        uint256 bidId = auction.submitBid{value: $bidAmount}(
            $maxPrice, $bidAmount, alice, tickNumberToPriceX96(1), bytes('')
        );

        vm.roll(auction.endBlock());
        Checkpoint memory checkpoint = auction.checkpoint();
        vm.assume($maxPrice > checkpoint.clearingPrice);

        auction.exitBid(bidId);

        // Check that exitedBlock is set
        Bid memory bid = auction.bids(bidId);
        assertEq(bid.exitedBlock, block.number);

        vm.expectRevert(IAuction.BidAlreadyExited.selector);
        auction.exitBid(bidId);
    }

    /// Simple test for a bid that partially fills at the clearing price but is the only bid at that price, functionally fully filled
    function test_exitPartiallyFilledBid_noOtherBidsAtClearingPrice_succeeds() public {
        uint256 bidId = auction.submitBid{value: inputAmountForTokens(1000e18, tickNumberToPriceX96(2))}(
            tickNumberToPriceX96(2),
            inputAmountForTokens(1000e18, tickNumberToPriceX96(2)),
            alice,
            tickNumberToPriceX96(1),
            bytes('')
        );
        vm.roll(block.number + 1);
        auction.checkpoint();

        uint256 aliceBalanceBefore = address(alice).balance;

        vm.roll(auction.endBlock());
        vm.prank(alice);
        // Checkpoint 2 is the previous last checkpointed block
        auction.exitPartiallyFilledBid(bidId, 1, 0);

        // Expect no refund
        assertEq(address(alice).balance, aliceBalanceBefore);

        vm.roll(auction.claimBlock());
        auction.claimTokens(bidId);
        assertEq(token.balanceOf(address(alice)), 1000e18);
    }

    /// forge-config: default.isolate = true
    /// forge-config: ci.isolate = true
    function test_exitPartiallyFilledBid_succeeds_gas() public {
        address bob = makeAddr('bob');
        uint256 bidId = auction.submitBid{value: inputAmountForTokens(500e18, tickNumberToPriceX96(11))}(
            tickNumberToPriceX96(11),
            inputAmountForTokens(500e18, tickNumberToPriceX96(11)),
            alice,
            tickNumberToPriceX96(1),
            bytes('')
        );
        uint256 bidId2 = auction.submitBid{value: inputAmountForTokens(500e18, tickNumberToPriceX96(21))}(
            tickNumberToPriceX96(21),
            inputAmountForTokens(500e18, tickNumberToPriceX96(21)),
            bob,
            tickNumberToPriceX96(11),
            bytes('')
        );

        // Clearing price is at 2
        vm.roll(block.number + 1);
        auction.checkpoint();
        assertEq(auction.clearingPrice(), tickNumberToPriceX96(11));

        uint256 aliceBalanceBefore = address(alice).balance;
        uint256 bobBalanceBefore = address(bob).balance;
        uint256 aliceTokenBalanceBefore = token.balanceOf(address(alice));
        uint256 bobTokenBalanceBefore = token.balanceOf(address(bob));

        vm.roll(auction.endBlock() + 1);
        vm.startPrank(alice);
        auction.exitPartiallyFilledBid(bidId, 1, 0);
        vm.snapshotGasLastCall('exitPartiallyFilledBid');
        // Alice is purchasing with 500e18 * 2000 = 1000e21 ETH
        // Bob is purchasing with 500e18 * 3000 = 1500e21 ETH
        // At a clearing price of 2e6
        // Since the supply is only 1000e18, that means that bob should fully fill for 750e18 tokens, and
        // Alice should partially fill for 250e18 tokens, spending 500e21 ETH
        // Meaning she should be refunded 1000e21 - 500e21 = 500e21 ETH
        assertEq(address(alice).balance, aliceBalanceBefore + 500e21);
        vm.roll(auction.claimBlock());
        auction.claimTokens(bidId);
        vm.snapshotGasLastCall('claimTokens');
        assertEq(token.balanceOf(address(alice)), aliceTokenBalanceBefore + 250e18);
        vm.stopPrank();

        vm.startPrank(bob);
        auction.exitBid(bidId2);
        vm.snapshotGasLastCall('exitBid');
        // Bob purchased 750e18 tokens for a price of 2, so they should have spent all of their ETH.
        assertEq(address(bob).balance, bobBalanceBefore + 0);
        vm.roll(auction.claimBlock());
        auction.claimTokens(bidId2);
        assertEq(token.balanceOf(address(bob)), bobTokenBalanceBefore + 750e18);
        vm.stopPrank();
    }

    function test_exitPartiallyFilledBid_multipleBidders_succeeds() public {
        address bob = makeAddr('bob');
        address charlie = makeAddr('charlie');
        uint256 bidId1 = auction.submitBid{value: inputAmountForTokens(400e18, tickNumberToPriceX96(11))}(
            tickNumberToPriceX96(11),
            inputAmountForTokens(400e18, tickNumberToPriceX96(11)),
            alice,
            tickNumberToPriceX96(1),
            bytes('')
        );
        uint256 bidId2 = auction.submitBid{value: inputAmountForTokens(600e18, tickNumberToPriceX96(11))}(
            tickNumberToPriceX96(11),
            inputAmountForTokens(600e18, tickNumberToPriceX96(11)),
            bob,
            tickNumberToPriceX96(1),
            bytes('')
        );

        // Not enough to move the price to 3, but to cause partial fills at 2
        uint256 bidId3 = auction.submitBid{value: inputAmountForTokens(500e18, tickNumberToPriceX96(21))}(
            tickNumberToPriceX96(21),
            inputAmountForTokens(500e18, tickNumberToPriceX96(21)),
            charlie,
            tickNumberToPriceX96(11),
            bytes('')
        );

        vm.roll(block.number + 1);
        auction.checkpoint();
        assertEq(auction.clearingPrice(), tickNumberToPriceX96(11));

        uint256 aliceBalanceBefore = address(alice).balance;
        uint256 bobBalanceBefore = address(bob).balance;
        uint256 charlieBalanceBefore = address(charlie).balance;
        uint256 aliceTokenBalanceBefore = token.balanceOf(address(alice));
        uint256 bobTokenBalanceBefore = token.balanceOf(address(bob));
        uint256 charlieTokenBalanceBefore = token.balanceOf(address(charlie));

        // Roll to end of auction
        vm.roll(auction.endBlock());
        uint256 expectedCurrencyRaised = inputAmountForTokens(750e18, tickNumberToPriceX96(11))
            + inputAmountForTokens(100e18, tickNumberToPriceX96(11))
            + inputAmountForTokens(150e18, tickNumberToPriceX96(11));

        vm.startPrank(auction.fundsRecipient());
        vm.expectEmit(true, true, true, true);
        emit ITokenCurrencyStorage.CurrencySwept(auction.fundsRecipient(), expectedCurrencyRaised);
        auction.sweepCurrency();
        vm.stopPrank();

        // Clearing price is at tick 21 = 2000
        // Alice is purchasing with 400e18 * 2000 = 800e21 ETH
        // Bob is purchasing with 600e18 * 2000 = 1200e21 ETH
        // Charlie is purchasing with 500e18 * 2000 = 1000e21 ETH
        //
        // At the clearing price of 2000
        // Charlie purchases 750e18 tokens
        // Remaining supply is 1000 - 750 = 250e18 tokens
        // Alice purchases 400/1000 * 250 = 100e18 tokens
        // - Spending 100e18 * 2000 = 200e21 ETH
        // - Refunded 800e21 - 200e21 = 600e21 ETH
        // Bob purchases 600/1000 * 250 = 150e18 tokens
        // - Spending 150e18 * 2000 = 300e21 ETH
        // - Refunded 1200e21 - 300e21 = 900e21 ETH
        vm.roll(auction.claimBlock());

        vm.startPrank(charlie);
        auction.exitBid(bidId3);
        assertEq(address(charlie).balance, charlieBalanceBefore + 0);
        auction.claimTokens(bidId3);
        assertEq(token.balanceOf(address(charlie)), charlieTokenBalanceBefore + 750e18);
        vm.stopPrank();

        vm.startPrank(alice);
        auction.exitPartiallyFilledBid(bidId1, 1, 0);
        assertEq(address(alice).balance, aliceBalanceBefore + 600e21);
        auction.claimTokens(bidId1);
        assertEq(token.balanceOf(address(alice)), aliceTokenBalanceBefore + 100e18);

        vm.startPrank(bob);
        auction.exitPartiallyFilledBid(bidId2, 1, 0);
        assertEq(address(bob).balance, bobBalanceBefore + 900e21);
        auction.claimTokens(bidId2);
        assertEq(token.balanceOf(address(bob)), bobTokenBalanceBefore + 150e18);
        vm.stopPrank();

        // All tokens were sold
        vm.expectEmit(true, true, true, true);
        emit ITokenCurrencyStorage.TokensSwept(auction.tokensRecipient(), 0);
        auction.sweepUnsoldTokens();
    }

    function test_exitPartiallyFilledBid_roundingError_succeeds() public {
        address bob = makeAddr('bob');
        address charlie = makeAddr('charlie');

        vm.roll(block.number + 1);
        uint256 bidId1 = auction.submitBid{value: inputAmountForTokens(400e18, tickNumberToPriceX96(5))}(
            tickNumberToPriceX96(5),
            inputAmountForTokens(400e18, tickNumberToPriceX96(5)),
            alice,
            tickNumberToPriceX96(1),
            bytes('')
        );

        vm.roll(block.number + 1);
        uint256 bidId2 = auction.submitBid{value: inputAmountForTokens(600e18, tickNumberToPriceX96(5))}(
            tickNumberToPriceX96(5),
            inputAmountForTokens(600e18, tickNumberToPriceX96(5)),
            bob,
            tickNumberToPriceX96(1),
            bytes('')
        );

        vm.roll(block.number + 1);
        // Not enough to move the price to 3, but to cause partial fills at 2
        uint256 bidId3 = auction.submitBid{value: inputAmountForTokens(500e18, tickNumberToPriceX96(6))}(
            tickNumberToPriceX96(6),
            inputAmountForTokens(500e18, tickNumberToPriceX96(6)),
            charlie,
            tickNumberToPriceX96(5),
            bytes('')
        );

        vm.roll(block.number + 1);
        uint256 bidId4 = auction.submitBid{value: inputAmountForTokens(1, tickNumberToPriceX96(6))}(
            tickNumberToPriceX96(6),
            inputAmountForTokens(1, tickNumberToPriceX96(6)),
            charlie,
            tickNumberToPriceX96(5),
            bytes('')
        );

        vm.roll(block.number + 1);
        auction.checkpoint();
        assertEq(auction.clearingPrice(), tickNumberToPriceX96(5));

        // Roll to end of auction
        vm.roll(auction.claimBlock());

        vm.startPrank(charlie);
        auction.exitBid(bidId3);
        auction.claimTokens(bidId3);
        auction.exitBid(bidId4);
        auction.claimTokens(bidId4);
        vm.stopPrank();

        vm.startPrank(alice);
        auction.exitPartiallyFilledBid(bidId1, 3, 0);
        auction.claimTokens(bidId1);
        vm.stopPrank();

        vm.startPrank(bob);
        auction.exitPartiallyFilledBid(bidId2, 3, 0);
        auction.claimTokens(bidId2);
        vm.stopPrank();

        // All tokens were sold
        vm.expectEmit(true, true, true, true);
        emit ITokenCurrencyStorage.TokensSwept(auction.tokensRecipient(), 0);
        auction.sweepUnsoldTokens();

        vm.startPrank(auction.fundsRecipient());
        auction.sweepCurrency();
        vm.stopPrank();
    }

    function test_exitPartiallyFilledBid_notGraduated_butOutbid_revertsWithNotGraduated() public {
        // Never graduate
        params = params.withRequiredCurrencyRaised(type(uint128).max);
        Auction newAuction = new Auction(address(token), TOTAL_SUPPLY, params);
        token.mint(address(newAuction), TOTAL_SUPPLY);
        newAuction.onTokensReceived();

        uint256 bidId1 = newAuction.submitBid{value: inputAmountForTokens(100e18, tickNumberToPriceX96(2))}(
            tickNumberToPriceX96(2),
            inputAmountForTokens(100e18, tickNumberToPriceX96(2)),
            alice,
            tickNumberToPriceX96(1),
            bytes('')
        );

        // Have bidId purchase some tokens
        vm.roll(block.number + 2);
        // Now outbid bidId1
        uint256 bidId2 = newAuction.submitBid{value: inputAmountForTokens(TOTAL_SUPPLY, tickNumberToPriceX96(3))}(
            tickNumberToPriceX96(3),
            inputAmountForTokens(TOTAL_SUPPLY, tickNumberToPriceX96(3)),
            alice,
            tickNumberToPriceX96(2),
            bytes('')
        );

        vm.roll(block.number + 1);
        newAuction.checkpoint();

        // Bid 1 is outbid and can be exited before the auction ends
        // however, auction is not graduated so cannot be exited
        vm.expectRevert(IAuction.CannotPartiallyExitBidBeforeGraduation.selector);
        newAuction.exitPartiallyFilledBid(bidId1, 3, 4);

        vm.roll(newAuction.endBlock());
        // Assert that the auction is not graduated
        assertEq(newAuction.isGraduated(), false);

        // Bid 1 can be exited as the auction is over
        uint256 expectedTokensFilled = 0;
        uint256 expectedCurrencyRefunded = inputAmountForTokens(100e18, tickNumberToPriceX96(2));
        vm.expectEmit(true, true, true, true);
        emit IAuction.BidExited(bidId1, alice, expectedTokensFilled, expectedCurrencyRefunded);
        newAuction.exitPartiallyFilledBid(bidId1, 3, 0);

        // Bid 2 ends at the final clearing price so can't be exited until the auction ends
        vm.expectEmit(true, true, true, true);
        expectedTokensFilled = 0;
        expectedCurrencyRefunded = inputAmountForTokens(TOTAL_SUPPLY, tickNumberToPriceX96(3));
        emit IAuction.BidExited(bidId2, alice, expectedTokensFilled, expectedCurrencyRefunded);
        newAuction.exitPartiallyFilledBid(bidId2, 3, 0);

        vm.roll(newAuction.claimBlock());
        vm.expectRevert(ITokenCurrencyStorage.NotGraduated.selector);
        newAuction.claimTokens(bidId1);
        vm.expectRevert(ITokenCurrencyStorage.NotGraduated.selector);
        newAuction.claimTokens(bidId2);

        // Expect all tokens were swept
        vm.expectEmit(true, true, true, true);
        emit ITokenCurrencyStorage.TokensSwept(newAuction.tokensRecipient(), TOTAL_SUPPLY);
        newAuction.sweepUnsoldTokens();
        assertEq(token.balanceOf(newAuction.tokensRecipient()), TOTAL_SUPPLY);

        // Expect no currency was swept
        vm.expectRevert(ITokenCurrencyStorage.NotGraduated.selector);
        newAuction.sweepCurrency();
        assertEq(address(newAuction).balance, 0);
    }

    function test_exitPartiallyFilledBid_notGraudated_endOfAuction_revertsWithNotGraduated() public {
        // Never graduate
        params = params.withRequiredCurrencyRaised(type(uint128).max);
        Auction newAuction = new Auction(address(token), TOTAL_SUPPLY, params);
        token.mint(address(newAuction), TOTAL_SUPPLY);
        newAuction.onTokensReceived();

        vm.roll(newAuction.startBlock());
        // Price ends at 2
        uint256 bidId = newAuction.submitBid{value: inputAmountForTokens(TOTAL_SUPPLY, tickNumberToPriceX96(2))}(
            tickNumberToPriceX96(2),
            inputAmountForTokens(TOTAL_SUPPLY, tickNumberToPriceX96(2)),
            alice,
            tickNumberToPriceX96(1),
            bytes('')
        );

        vm.roll(block.number + 1);
        // Assert that the auction is not graduated
        assertEq(newAuction.isGraduated(), false);
        // And that the bid cannot be exited
        vm.expectRevert(IAuction.CannotPartiallyExitBidBeforeGraduation.selector);
        newAuction.exitPartiallyFilledBid(bidId, 1, 0);

        vm.roll(newAuction.endBlock());
        // Assert that the auction is not graduated
        assertEq(newAuction.isGraduated(), false);
        Checkpoint memory finalCheckpoint = newAuction.checkpoint();
        assertEq(finalCheckpoint.clearingPrice, tickNumberToPriceX96(2));

        // Bid can be exited as the auction is over
        vm.expectEmit(true, true, true, true);
        uint256 expectedTokensFilled = 0;
        uint256 expectedCurrencyRefunded = inputAmountForTokens(TOTAL_SUPPLY, tickNumberToPriceX96(2));
        emit IAuction.BidExited(bidId, alice, expectedTokensFilled, expectedCurrencyRefunded);
        newAuction.exitPartiallyFilledBid(bidId, 1, 0);
    }

    function test_onTokensReceived_repeatedCall_succeeds() public {
        address bob = makeAddr('bob');
        uint256 balance = token.balanceOf(address(auction));
        vm.prank(address(auction));
        // Unset the balance of the auction
        token.transfer(bob, balance);
        // No revert happens, no event is emitted
        auction.onTokensReceived();
    }

    function test_onTokensReceived_withWrongBalance_reverts() public {
        // Use salt to get a new address
        Auction newAuction = new Auction{salt: bytes32(uint256(1))}(address(token), TOTAL_SUPPLY, params);

        token.mint(address(newAuction), TOTAL_SUPPLY - 1);

        vm.expectRevert(IAuction.InvalidTokenAmountReceived.selector);
        newAuction.onTokensReceived();
    }

    /// forge-config: default.isolate = true
    /// forge-config: ci.isolate = true
    function test_advanceToCurrentStep_withClearingPriceZero_gas() public {
        params = params.withAuctionStepsData(
            AuctionStepsBuilder.init().addStep(100e3, 10).addStep(100e3, 40).addStep(100e3, 50)
        );

        Auction newAuction = new Auction(address(token), TOTAL_SUPPLY, params);
        token.mint(address(newAuction), TOTAL_SUPPLY);
        newAuction.onTokensReceived();

        // Advance to middle of step without any bids (clearing price = 0)
        vm.roll(block.number + 50);
        newAuction.checkpoint();
        vm.snapshotGasLastCall('checkpoint_advanceToCurrentStep');

        // Should not have transformed checkpoint since clearing price is 0
        // The clearing price will be set to floor price when first checkpoint is created
        assertEq(newAuction.clearingPrice(), FLOOR_PRICE);
    }

    /// forge-config: default.isolate = true
    /// forge-config: ci.isolate = true
    function test_checkpoint_withNoDemand() public {
        // Don't submit any bids
        vm.roll(block.number + 1);
        auction.checkpoint();
        vm.snapshotGasLastCall('checkpoint_noBids');

        // Clearing price should be floor price
        assertEq(auction.clearingPrice(), auction.floorPrice());
    }

    function test_exitPartiallyFilledBid_withInvalidOutbidBlockCheckpointHint_reverts() public {
        // Submit a bid at price 2
        uint256 bidId = auction.submitBid{value: inputAmountForTokens(100e18, tickNumberToPriceX96(2))}(
            tickNumberToPriceX96(2),
            inputAmountForTokens(100e18, tickNumberToPriceX96(2)),
            alice,
            tickNumberToPriceX96(1),
            bytes('')
        );

        vm.roll(block.number + 1);
        auction.checkpoint(); // This creates checkpoint 2 with clearing price = tickNumberToPriceX96(2)

        // Submit a larger bid to move clearing price above the first bid
        auction.submitBid{value: inputAmountForTokens(1000e18, tickNumberToPriceX96(3))}(
            tickNumberToPriceX96(3),
            inputAmountForTokens(1000e18, tickNumberToPriceX96(3)),
            alice,
            tickNumberToPriceX96(2),
            bytes('')
        );

        vm.roll(block.number + 1);
        auction.checkpoint(); // This creates checkpoint 3 with clearing price = tickNumberToPriceX96(3)

        vm.roll(auction.endBlock() + 1);
        // Try to exit with checkpoint 2 as the outbid checkpoint
        // But checkpoint 2 has clearing price = tickNumberToPriceX96(2), which equals bid.maxPrice
        // This violates the condition: outbidCheckpoint.clearingPrice < bid.maxPrice
        vm.expectRevert(IAuction.InvalidOutbidBlockCheckpointHint.selector);
        auction.exitPartiallyFilledBid(bidId, 2, 2);
    }

    function test_exitPartiallyfilledBid_outbid_succeeds() public {
        uint256 bidId = auction.submitBid{value: inputAmountForTokens(1, tickNumberToPriceX96(2))}(
            tickNumberToPriceX96(2),
            inputAmountForTokens(1, tickNumberToPriceX96(2)),
            alice,
            tickNumberToPriceX96(1),
            bytes('')
        );

        vm.roll(block.number + 1);
        auction.submitBid{value: inputAmountForTokens(TOTAL_SUPPLY, tickNumberToPriceX96(3))}(
            tickNumberToPriceX96(3),
            inputAmountForTokens(TOTAL_SUPPLY, tickNumberToPriceX96(3)),
            alice,
            tickNumberToPriceX96(2),
            bytes('')
        );

        vm.roll(block.number + 1);
        auction.checkpoint();

        // Bid 1 should be immediately exitable because it has been outbid
        auction.exitPartiallyFilledBid(bidId, 2, 3);
    }

    function test_exitPartiallyfilledBid_outbidBlockIsCurrentBlock_succeeds() public {
        uint256 bidId = auction.submitBid{value: inputAmountForTokens(1, tickNumberToPriceX96(2))}(
            tickNumberToPriceX96(2),
            inputAmountForTokens(1, tickNumberToPriceX96(2)),
            alice,
            tickNumberToPriceX96(1),
            bytes('')
        );

        vm.roll(block.number + 1);
        auction.submitBid{value: inputAmountForTokens(TOTAL_SUPPLY, tickNumberToPriceX96(3))}(
            tickNumberToPriceX96(3),
            inputAmountForTokens(TOTAL_SUPPLY, tickNumberToPriceX96(3)),
            alice,
            tickNumberToPriceX96(2),
            bytes('')
        );

        vm.roll(block.number + 1);
        // Lower hint is the last fully filled checkpoint (2), since it includes the first bid but not the second
        // Outbid checkpoint block is the current block (3)
        auction.exitPartiallyFilledBid(bidId, 2, uint64(block.number));
    }

    function test_exitPartiallyfilledBid_withHigherOutbidBlockHint_reverts() public {
        uint256 bidId = auction.submitBid{value: inputAmountForTokens(1, tickNumberToPriceX96(2))}(
            tickNumberToPriceX96(2),
            inputAmountForTokens(1, tickNumberToPriceX96(2)),
            alice,
            tickNumberToPriceX96(1),
            bytes('')
        );

        vm.roll(block.number + 1);
        auction.submitBid{value: inputAmountForTokens(TOTAL_SUPPLY, tickNumberToPriceX96(3))}(
            tickNumberToPriceX96(3),
            inputAmountForTokens(TOTAL_SUPPLY, tickNumberToPriceX96(3)),
            alice,
            tickNumberToPriceX96(2),
            bytes('')
        );

        vm.roll(block.number + 1);
        // Block 3 is the correct first outbid block
        auction.checkpoint();

        vm.roll(block.number + 1);
        // While the bid is outbid as of block 4, it is an incorrect hint
        auction.checkpoint();

        vm.expectRevert(IAuction.InvalidOutbidBlockCheckpointHint.selector);
        auction.exitPartiallyFilledBid(bidId, 2, uint64(block.number));

        // Expect the revert to still happen at the endBlock
        vm.roll(auction.endBlock());
        vm.expectRevert(IAuction.InvalidOutbidBlockCheckpointHint.selector);
        auction.exitPartiallyFilledBid(bidId, 2, uint64(block.number));

        // As well as after the endBlock
        vm.roll(auction.endBlock() + 1);
        uint64 endBlock = uint64(auction.endBlock());
        vm.expectRevert(IAuction.InvalidOutbidBlockCheckpointHint.selector);
        auction.exitPartiallyFilledBid(bidId, 2, endBlock);
    }

    function test_exitPartiallyFilledBid_finalCheckpointPriceEqual_revertsWithCannotPartiallyExitBidBeforeEndBlock()
        public
    {
        uint256 bidId = auction.submitBid{value: inputAmountForTokens(TOTAL_SUPPLY, tickNumberToPriceX96(2))}(
            tickNumberToPriceX96(2),
            inputAmountForTokens(TOTAL_SUPPLY, tickNumberToPriceX96(2)),
            alice,
            tickNumberToPriceX96(1),
            bytes('')
        );

        vm.roll(auction.endBlock() - 1);
        auction.checkpoint();

        vm.expectRevert(IAuction.CannotPartiallyExitBidBeforeEndBlock.selector);
        // Checkpoint hints are:
        // - lower: 1 (last fully filled checkpoint)
        // - upper: 0 because the bid was never outbid
        auction.exitPartiallyFilledBid(bidId, 1, 0);
    }

    function test_exitPartiallyFilledBid_finalCheckpointPriceEqual_succeeds() public {
        uint256 bidId = auction.submitBid{value: inputAmountForTokens(TOTAL_SUPPLY, tickNumberToPriceX96(2))}(
            tickNumberToPriceX96(2),
            inputAmountForTokens(TOTAL_SUPPLY, tickNumberToPriceX96(2)),
            alice,
            tickNumberToPriceX96(1),
            bytes('')
        );

        // We need to checkpoint after the bid is submitted since otherwise the check on lastFullyFilledCheckpoint.next will revert
        vm.roll(block.number + 1);
        auction.checkpoint();

        vm.roll(auction.endBlock());
        // Expect the final checkpoint to be made
        vm.expectEmit(true, true, true, true);
        uint24 expectedCumulativeMps = ConstantsLib.MPS;
        ValueX7 expectedTotalCurrencyRaised = ValueX7.wrap(TOTAL_SUPPLY_Q96)
            .wrapAndFullMulDiv(tickNumberToPriceX96(2) * expectedCumulativeMps, FixedPoint96.Q96);
        emit IAuction.CheckpointUpdated(
            block.number, tickNumberToPriceX96(2), expectedTotalCurrencyRaised, expectedCumulativeMps
        );
        // Checkpoint hints are:
        // - lower: 1 (last fully filled checkpoint)
        // - upper: 0 because the bid was never outbid
        auction.exitPartiallyFilledBid(bidId, 1, 0);
    }

    function test_exitPartiallyFilledBid_lowerHintIsValidated() public {
        MockAuction mockAuction = new MockAuction(address(token), TOTAL_SUPPLY, params);
        token.mint(address(mockAuction), TOTAL_SUPPLY);
        mockAuction.onTokensReceived();

        Checkpoint memory _checkpointOne;
        _checkpointOne.clearingPrice = tickNumberToPriceX96(1);
        Checkpoint memory _checkpointTwo;
        _checkpointTwo.clearingPrice = tickNumberToPriceX96(2);
        Checkpoint memory _checkpointThree;
        _checkpointThree.clearingPrice = tickNumberToPriceX96(2);
        Checkpoint memory _checkpointFour;
        _checkpointFour.clearingPrice = tickNumberToPriceX96(2);
        Checkpoint memory _checkpointFive;
        _checkpointFive.clearingPrice = tickNumberToPriceX96(3);

        vm.roll(1);
        // Create a bid which was entered with a max price of tickNumberToPriceX96(2) at checkpoint 1
        (Bid memory bid, uint256 bidId) = mockAuction.uncheckedCreateBid(100e18, alice, tickNumberToPriceX96(2), 0);
        assertEq(bid.startBlock, 1);
        mockAuction.insertCheckpoint(_checkpointOne, 1);
        vm.roll(2);
        mockAuction.insertCheckpoint(_checkpointTwo, 2);
        vm.roll(3);
        mockAuction.insertCheckpoint(_checkpointThree, 3);
        vm.roll(4);
        mockAuction.insertCheckpoint(_checkpointFour, 4);
        vm.roll(5);
        mockAuction.insertCheckpoint(_checkpointFive, 5);

        // The bid is fully filled at checkpoint 1
        // The bid is partially filled from checkpoints (2, 3, 4), inclusive
        // The bid is outbid at checkpoint 5

        // Test failure cases
        // Provide an invalid lower hint (i being not 1)
        for (uint64 i = 0; i <= 5; i++) {
            if (i == 1) continue;
            vm.expectRevert(IAuction.InvalidLastFullyFilledCheckpointHint.selector);
            mockAuction.exitPartiallyFilledBid(bidId, i, 5);
        }
    }

    function test_advanceToCurrentStep_withMultipleStepsAndClearingPrice() public {
        params = params.withEndBlock(block.number + 60)
            .withAuctionStepsData(AuctionStepsBuilder.init().addStep(100e3, 20).addStep(150e3, 20).addStep(250e3, 20));

        Auction newAuction = new Auction(address(token), TOTAL_SUPPLY, params);
        token.mint(address(newAuction), TOTAL_SUPPLY);
        newAuction.onTokensReceived();

        newAuction.submitBid{value: inputAmountForTokens(100e18, tickNumberToPriceX96(2))}(
            tickNumberToPriceX96(2),
            inputAmountForTokens(100e18, tickNumberToPriceX96(2)),
            alice,
            tickNumberToPriceX96(1),
            bytes('')
        );

        vm.roll(block.number + 10);
        newAuction.checkpoint();

        vm.roll(block.number + 15);
        newAuction.checkpoint();

        uint24 mps = newAuction.step().mps;
        assertEq(mps, 150e3);

        vm.roll(block.number + 20);
        newAuction.checkpoint();

        AuctionStep memory step = newAuction.step();
        assertEq(step.mps, 250e3);
    }

    // Test the edge case where the blockNumber happens to be on the end of a step, which is exclusive
    // Test the case where the current step is 0 mps and we have to call advanceToCurrentStep before calculating the clearing price
    function test_advanceToCurrentStep_blockNumberIsEndOfZeroMpsStep() public {
        // 10 blocks of 0 mps, then 100 blocks of 100e3 mps (1%) each
        uint64 startBlock = uint64(block.number);
        uint64 endBlock = startBlock + 110;
        params = params.withAuctionStepsData(AuctionStepsBuilder.init().addStep(0, 10).addStep(100e3, 100))
            .withEndBlock(block.number + 110);
        MockAuction mockAuction = new MockAuction(address(token), TOTAL_SUPPLY, params);
        token.mint(address(mockAuction), TOTAL_SUPPLY);
        mockAuction.onTokensReceived();

        AuctionStep memory step = mockAuction.step();
        assertEq(step.mps, 0);
        assertEq(step.startBlock, startBlock);
        assertEq(step.endBlock, startBlock + 10);

        /**
         * Current state of the auction steps
         * blockNumber:     1                11                                    111
         *                  |                |                                      |
         *          stepStart          stepEnd
         *                             stepStart                              stepEnd
         *                  ^
         */
        // Roll to the end of the first step (top of block)
        vm.roll(step.endBlock);
        /**
         * blockNumber:     1                11                                    111
         *                  |                |                                      |
         *          stepStart          stepEnd
         *                             stepStart                              stepEnd
         *                                   ^
         * We are at the END of the first step, which is the start of the second step
         * If we make a checkpoint in this block (number 11), which step is valid?
         * - It should be the second step, because AuctionSteps are inclusive of the start block and exclusive of the end block
         *   So for blocks [1, 10), we sold 0 mps for blocks 1,2,3,4,5,6,7,8,9,10
         * Since Checkpoints are made top of the block, they reflect the state of the auction UP UNTIL, but not including, that block.
         *
         * Thus the bid below makes a checkpoint which does not show that any mps or tokens have been sold (because they haven't).
         */
        vm.expectEmit(true, true, true, true);
        // Assert that there is no supply sold in this checkpoint
        emit IAuction.CheckpointUpdated(block.number, tickNumberToPriceX96(1), ValueX7.wrap(0), 0);
        uint256 bidId = mockAuction.submitBid{value: inputAmountForTokens(TOTAL_SUPPLY, tickNumberToPriceX96(2))}(
            tickNumberToPriceX96(2),
            inputAmountForTokens(TOTAL_SUPPLY, tickNumberToPriceX96(2)),
            alice,
            tickNumberToPriceX96(1),
            bytes('')
        );
        uint256 sumCurrencyDemandAboveClearingQ96 = mockAuction.sumCurrencyDemandAboveClearingQ96();
        // Demand should be the same as the bid demand
        assertEq(sumCurrencyDemandAboveClearingQ96, mockAuction.getBid(bidId).toEffectiveAmount());
        /**
         * Roll one more block and checkpoint
         * blockNumber:     1                11   12                              111
         *                  |                |     .                                |
         *          stepStart          stepEnd
         *                             stepStart                              stepEnd
         *                                         ^
         * The current block number is 12, which is > than the end of the current step (ended block 11). That means we have to advance forward
         * Before we can advance to the next step, there could have been blocks that were not checkpointed in between the last checkpoint we made
         * and the end of the last step. In this case both of those values are equal (block 11) so we don't transform the checkpoint.
         * However, we do advance to the next step such that the step is up to date with the schedule.
         *
         * Once the step is made current, we can find the `clearingPrice` and `sumCurrencyDemandAboveClearingQ96` values which affect the Checkpointed values.
         * It's important to remember that these values are calculated at the TOP of block 12, one block after the bid was submitted
         * This is correct because it reflects the state of the auction UP UNTIL block 12, not including.
         *
         * And we show that at the end of the last step of the auction, 1e7 or 100% of all `mps` were sold in the auction
         */
        vm.roll(block.number + 1);
        vm.expectEmit(true, true, true, true);
        // Expect the second step to be recorded
        emit IAuctionStepStorage.AuctionStepRecorded(step.endBlock, endBlock, 100e3);
        mockAuction.checkpoint();

        // Roll to end of the auction
        vm.roll(endBlock);
        vm.expectEmit(true, true, true, true);
        // Expect that we sold the total supply at price of 2
        emit IAuction.CheckpointUpdated(
            block.number,
            tickNumberToPriceX96(2),
            ValueX7.wrap(TOTAL_SUPPLY_Q96)
                .wrapAndFullMulDivUp(tickNumberToPriceX96(2) * ConstantsLib.MPS, FixedPoint96.Q96),
            ConstantsLib.MPS
        );
        mockAuction.checkpoint();
    }

    function test_advanceToCurrentStep_blockNumberIsEndOfStep() public {
        uint64 startBlock = uint64(block.number);
        uint64 endBlock = startBlock + 40;
        params = params.withAuctionStepsData(AuctionStepsBuilder.init().addStep(100e3, 10).addStep(300e3, 30))
            .withEndBlock(block.number + 40);
        MockAuction mockAuction = new MockAuction(address(token), TOTAL_SUPPLY, params);
        token.mint(address(mockAuction), TOTAL_SUPPLY);
        mockAuction.onTokensReceived();

        AuctionStep memory step = mockAuction.step();
        assertEq(step.mps, 100e3);
        assertEq(step.startBlock, startBlock);
        assertEq(step.endBlock, startBlock + 10);

        /**
         * Current state of the auction steps
         * blockNumber:     1                11                                    111
         *                  |                |                                      |
         *          stepStart          stepEnd
         *                             stepStart                              stepEnd
         *                  ^
         */
        // Roll to the end of the first step (top of block)
        vm.roll(step.endBlock);
        /**
         * blockNumber:     1                11                                    111
         *                  |                |                                      |
         *          stepStart          stepEnd
         *                             stepStart                              stepEnd
         *                                   ^
         * We are at the END of the first step, which is the start of the second step
         * If we make a checkpoint in this block (number 11), which step is valid?
         * - It should be the second step, because AuctionSteps are inclusive of the start block and exclusive of the end block
         *   So for blocks [1, 10), we sold 100e3 mps for blocks 1,2,3,4,5,6,7,8,9,10
         * Since Checkpoints are made top of the block, they reflect the state of the auction UP UNTIL, but not including, that block.
         *
         * Thus the bid below makes a checkpoint which shows that 100e3 * 10 mps were sold but no supply was cleared
         */
        vm.expectEmit(true, true, true, true);
        emit IAuction.CheckpointUpdated(block.number, tickNumberToPriceX96(1), ValueX7.wrap(0), 100e3 * 10);
        uint256 bidId = mockAuction.submitBid{value: inputAmountForTokens(TOTAL_SUPPLY, tickNumberToPriceX96(2))}(
            tickNumberToPriceX96(2),
            inputAmountForTokens(TOTAL_SUPPLY, tickNumberToPriceX96(2)),
            alice,
            tickNumberToPriceX96(1),
            bytes('')
        );
        uint256 sumCurrencyDemandAboveClearingQ96 = mockAuction.sumCurrencyDemandAboveClearingQ96();
        // Demand should be the same as the bid demand
        assertEq(sumCurrencyDemandAboveClearingQ96, mockAuction.getBid(bidId).toEffectiveAmount());
        /**
         * Roll one more block and checkpoint
         * blockNumber:     1                11   12                              111
         *                  |                |     .                                |
         *          stepStart          stepEnd
         *                             stepStart                              stepEnd
         *                                         ^
         * The current block number is 12, which is > than the end of the current step (ended block 11). That means we have to advance forward
         * Before we can advance to the next step, there could have been blocks that were not checkpointed in between the last checkpoint we made
         * and the end of the last step. In this case both of those values are equal (block 11) so we don't transform the checkpoint.
         * However, we do advance to the next step such that the step is up to date with the schedule.
         *
         * Once the step is made current, we can find the `clearingPrice` and `sumCurrencyDemandAboveClearingQ96` values which affect the Checkpointed values.
         * It's important to remember that these values are calculated at the TOP of block 12, one block after the bid was submitted
         * This is correct because it reflects the state of the auction UP UNTIL block 12, not including.
         *
         * And we show that at the end of the last step of the auction, 1e7 or 100% of all `mps` were sold in the auction
         */
        vm.roll(block.number + 1);
        vm.expectEmit(true, true, true, true);
        // Expect the second step to be recorded
        emit IAuctionStepStorage.AuctionStepRecorded(step.endBlock, endBlock, 300e3);
        mockAuction.checkpoint();

        // Roll to end of the auction
        vm.roll(endBlock);
        // Since there is no rollover and we skipped the first 10% of the auction, we expect to sell 90% of the total supply
        vm.expectEmit(true, true, true, true);
        ValueX7 expectedTotalCurrencyRaised = ValueX7.wrap(TOTAL_SUPPLY_Q96)
            .wrapAndFullMulDivUp(tickNumberToPriceX96(2) * (ConstantsLib.MPS - 100e3 * 10), FixedPoint96.Q96);
        emit IAuction.CheckpointUpdated( // Yet the `cumulativeMps` should still be 100%
            startBlock + 40, tickNumberToPriceX96(2), expectedTotalCurrencyRaised, ConstantsLib.MPS
        );
        mockAuction.checkpoint();
    }

    /// forge-config: default.isolate = true
    /// forge-config: ci.isolate = true
    function test_submitBid_withValidationHook_callsValidationHook_gas() public {
        // Create a mock validation hook
        MockValidationHook validationHook = new MockValidationHook();

        // Create auction parameters with the validation hook
        params = params.withValidationHook(address(validationHook));

        Auction testAuction = new Auction(address(token), TOTAL_SUPPLY, params);
        token.mint(address(testAuction), TOTAL_SUPPLY);
        testAuction.onTokensReceived();
        // Submit a bid with hook data to trigger the validation hook
        uint256 bidId = testAuction.submitBid{value: inputAmountForTokens(100e18, tickNumberToPriceX96(2))}(
            tickNumberToPriceX96(2),
            inputAmountForTokens(100e18, tickNumberToPriceX96(2)),
            alice,
            tickNumberToPriceX96(1),
            bytes('hook data')
        );
        vm.snapshotGasLastCall('submitBid_withValidationHook');

        assertEq(bidId, 0);
    }

    function test_submitBid_withERC20Currency_unpermittedPermit2Transfer_reverts() public {
        // Create auction parameters with ERC20 currency instead of ETH
        params = params.withCurrency(address(erc20Currency));
        Auction erc20Auction = new Auction(address(token), TOTAL_SUPPLY, params);
        token.mint(address(erc20Auction), TOTAL_SUPPLY);
        erc20Auction.onTokensReceived();
        // Mint currency tokens to alice
        erc20Currency.mint(alice, 1000e18);

        // For now, let's just verify that the currency is set correctly
        // and that we would reach line 252 if the Permit2 transfer worked
        assertEq(Currency.unwrap(erc20Auction.currency()), address(erc20Currency));
        assertFalse(erc20Auction.currency().isAddressZero());

        vm.expectRevert(SafeTransferLib.TransferFromFailed.selector); // Expect revert due to Permit2 transfer failure
        erc20Auction.submitBid{value: 0}(
            tickNumberToPriceX96(2),
            inputAmountForTokens(100e18, tickNumberToPriceX96(2)),
            alice,
            tickNumberToPriceX96(1),
            bytes('')
        );
    }

    function test_submitBid_withERC20Currency_nonZeroMsgValue_reverts() public {
        // Create auction parameters with ERC20 currency instead of ETH
        params = params.withCurrency(address(erc20Currency));
        Auction erc20Auction = new Auction(address(token), TOTAL_SUPPLY, params);
        token.mint(address(erc20Auction), TOTAL_SUPPLY);
        erc20Auction.onTokensReceived();

        // Mint currency tokens to alice
        erc20Currency.mint(alice, 1000e18);

        // For now, let's just verify that the currency is set correctly
        assertEq(Currency.unwrap(erc20Auction.currency()), address(erc20Currency));
        assertFalse(erc20Auction.currency().isAddressZero());

        vm.expectRevert(IAuction.CurrencyIsNotNative.selector);
        erc20Auction.submitBid{value: 100e18}(
            tickNumberToPriceX96(2),
            inputAmountForTokens(100e18, tickNumberToPriceX96(2)),
            alice,
            tickNumberToPriceX96(1),
            bytes('')
        );
    }

    function test_exitPartiallyFilledBid_withInvalidLowerCheckpointHint_atEndBlock_reverts() public {
        uint256 bidId = auction.submitBid{value: inputAmountForTokens(100e18, tickNumberToPriceX96(2))}(
            tickNumberToPriceX96(2),
            inputAmountForTokens(100e18, tickNumberToPriceX96(2)),
            alice,
            tickNumberToPriceX96(1),
            bytes('')
        );

        vm.roll(block.number + 1);
        auction.checkpoint();

        vm.roll(auction.endBlock() + 1);
        vm.expectRevert(IAuction.InvalidLastFullyFilledCheckpointHint.selector);
        auction.exitPartiallyFilledBid(bidId, 2, 2);
    }

    function test_auctionConstruction_revertsWithTotalSupplyZero() public {
        vm.expectRevert(ITokenCurrencyStorage.TotalSupplyIsZero.selector);
        new Auction(address(token), 0, params);
    }

    function test_auctionConstruction_revertsWithTickSpacingTooSmall_fuzz(uint256 _tickSpacing) public {
        _tickSpacing = _bound(_tickSpacing, 0, 1);
        AuctionParameters memory paramsTickSpacingTooSmall = params.withTickSpacing(_tickSpacing);
        vm.expectRevert(ITickStorage.TickSpacingTooSmall.selector);
        new Auction(address(token), TOTAL_SUPPLY, paramsTickSpacingTooSmall);
    }

    function test_auctionConstruction_revertsWithFloorPriceZero() public {
        AuctionParameters memory paramsZeroFloorPrice = params.withFloorPrice(0);
        vm.expectRevert(ITickStorage.FloorPriceIsZero.selector);
        new Auction(address(token), TOTAL_SUPPLY, paramsZeroFloorPrice);
    }

    function test_auctionConstruction_revertsWithClaimBlockBeforeEndBlock() public {
        AuctionParameters memory paramsClaimBlockBeforeEndBlock =
            params.withClaimBlock(block.number + AUCTION_DURATION - 1).withEndBlock(block.number + AUCTION_DURATION);
        vm.expectRevert(IAuction.ClaimBlockIsBeforeEndBlock.selector);
        new Auction(address(token), TOTAL_SUPPLY, paramsClaimBlockBeforeEndBlock);
    }

    function test_auctionConstruction_revertsWithFundsRecipientZero() public {
        AuctionParameters memory paramsFundsRecipientZero = params.withFundsRecipient(address(0));
        vm.expectRevert(ITokenCurrencyStorage.FundsRecipientIsZero.selector);
        new Auction(address(token), TOTAL_SUPPLY, paramsFundsRecipientZero);
    }

    function test_auctionConstruction_revertsWithTokensRecipientZero() public {
        AuctionParameters memory paramsTokensRecipientZero = params.withTokensRecipient(address(0));
        vm.expectRevert(ITokenCurrencyStorage.TokensRecipientIsZero.selector);
        new Auction(address(token), TOTAL_SUPPLY, paramsTokensRecipientZero);
    }

    function test_checkpoint_beforeAuctionStarts_reverts() public {
        // Create an auction that starts in the future
        uint256 futureBlock = block.number + 10;
        params = params.withStartBlock(futureBlock).withEndBlock(futureBlock + AUCTION_DURATION)
            .withClaimBlock(futureBlock + AUCTION_DURATION);

        Auction futureAuction = new Auction(address(token), TOTAL_SUPPLY, params);
        token.mint(address(futureAuction), TOTAL_SUPPLY);

        // Try to call checkpoint before the auction starts
        vm.expectRevert(IAuction.AuctionNotStarted.selector);
        futureAuction.checkpoint();
    }

    function test_submitBid_afterAuctionEnds_reverts() public {
        // Advance to after the auction ends
        vm.roll(auction.endBlock() + 1);

        // Try to submit a bid after the auction has ended
        vm.expectRevert(IAuctionStepStorage.AuctionIsOver.selector);
        auction.submitBid{value: inputAmountForTokens(100e18, tickNumberToPriceX96(2))}(
            tickNumberToPriceX96(2),
            inputAmountForTokens(100e18, tickNumberToPriceX96(2)),
            alice,
            tickNumberToPriceX96(1),
            bytes('')
        );
    }

    function test_submitBid_atEndBlock_reverts() public {
        // Advance to the auction end block
        vm.roll(auction.endBlock());

        // Try to submit a bid at the end block
        vm.expectRevert(IAuctionStepStorage.AuctionIsOver.selector);
        auction.submitBid{value: inputAmountForTokens(100e18, tickNumberToPriceX96(2))}(
            tickNumberToPriceX96(2),
            inputAmountForTokens(100e18, tickNumberToPriceX96(2)),
            alice,
            tickNumberToPriceX96(1),
            bytes('')
        );
    }

    function test_submitBid_afterEndBlock_reverts() public {
        // Advance to after the auction end block
        vm.roll(auction.endBlock() + 1);

        // Try to submit a bid after the auction end block
        vm.expectRevert(IAuctionStepStorage.AuctionIsOver.selector);
        auction.submitBid{value: inputAmountForTokens(100e18, tickNumberToPriceX96(2))}(
            tickNumberToPriceX96(2),
            inputAmountForTokens(100e18, tickNumberToPriceX96(2)),
            alice,
            tickNumberToPriceX96(1),
            bytes('')
        );
    }

    function test_exitPartiallyFilledBid_alreadyExited_reverts() public {
        // Use the same pattern as the working test_exitPartiallyFilledBid_succeeds_gas
        address bob = makeAddr('bob');
        uint256 bidId = auction.submitBid{value: inputAmountForTokens(500e18, tickNumberToPriceX96(2))}(
            tickNumberToPriceX96(2),
            inputAmountForTokens(500e18, tickNumberToPriceX96(2)),
            alice,
            tickNumberToPriceX96(1),
            bytes('')
        );
        auction.submitBid{value: inputAmountForTokens(500e18, tickNumberToPriceX96(3))}(
            tickNumberToPriceX96(3),
            inputAmountForTokens(500e18, tickNumberToPriceX96(3)),
            bob,
            tickNumberToPriceX96(2),
            bytes('')
        );

        // Clearing price is at 2
        vm.roll(block.number + 1);
        auction.checkpoint();

        vm.roll(auction.endBlock() + 1);
        vm.startPrank(alice);

        // Exit the bid once - this should succeed
        auction.exitPartiallyFilledBid(bidId, 1, 0);

        // Check that exitedBlock is set
        Bid memory bid = auction.bids(bidId);
        assertEq(bid.exitedBlock, block.number);

        vm.expectRevert(IAuction.BidAlreadyExited.selector);
        auction.exitPartiallyFilledBid(bidId, 1, 0);

        vm.stopPrank();
    }

    function test_exitPartiallyFilledBid_notGraduated_endOfAuction_revertsWithAlreadyExited() public {
        // Never graduate
        params = params.withRequiredCurrencyRaised(type(uint128).max);
        Auction newAuction = new Auction(address(token), TOTAL_SUPPLY, params);
        token.mint(address(newAuction), TOTAL_SUPPLY);
        newAuction.onTokensReceived();

        uint256 bidId = newAuction.submitBid{value: inputAmountForTokens(100e18, tickNumberToPriceX96(2))}(
            tickNumberToPriceX96(2),
            inputAmountForTokens(100e18, tickNumberToPriceX96(2)),
            alice,
            tickNumberToPriceX96(1),
            bytes('')
        );

        vm.roll(newAuction.endBlock());
        assertEq(newAuction.isGraduated(), false);

        vm.expectEmit(true, true, true, true);
        uint256 expectedTokensFilled = 0;
        uint256 expectedCurrencyRefunded = inputAmountForTokens(100e18, tickNumberToPriceX96(2));
        emit IAuction.BidExited(bidId, alice, expectedTokensFilled, expectedCurrencyRefunded);
        newAuction.exitPartiallyFilledBid(bidId, 1, 0);

        // Check that exitedBlock is set
        Bid memory bid = newAuction.bids(bidId);
        assertEq(bid.exitedBlock, block.number);

        // Expect that you can't exit the bid again
        vm.expectRevert(IAuction.BidAlreadyExited.selector);
        newAuction.exitPartiallyFilledBid(bidId, 1, 0);
    }

    /// forge-config: default.fuzz.runs = 1000
    /// forge-config: ci.fuzz.runs = 1000
    function test_claimTokens_beforeBidExited_reverts(uint128 _bidAmount, uint256 _maxPrice)
        public
        givenValidMaxPrice(_maxPrice, TOTAL_SUPPLY)
        givenValidBidAmount(_bidAmount)
        givenGraduatedAuction
        givenFullyFundedAccount
    {
        // Submit a bid but don't exit it
        uint256 bidId =
            auction.submitBid{value: $bidAmount}($maxPrice, $bidAmount, alice, tickNumberToPriceX96(1), bytes(''));

        // Try to claim tokens before the bid has been exited
        vm.roll(auction.claimBlock());
        vm.startPrank(alice);
        vm.expectRevert(IAuction.BidNotExited.selector);
        auction.claimTokens(bidId);
        vm.stopPrank();
    }

    function test_claimTokens_beforeClaimBlock_reverts(uint128 _bidAmount, uint128 _maxPrice)
        public
        givenValidMaxPrice(_maxPrice, TOTAL_SUPPLY)
        givenValidBidAmount(_bidAmount)
        givenGraduatedAuction
        givenFullyFundedAccount
    {
        uint256 bidId = auction.submitBid{value: $bidAmount}(
            $maxPrice, $bidAmount, alice, tickNumberToPriceX96(1), bytes('')
        );

        // Exit the bid
        vm.roll(auction.endBlock());
        Checkpoint memory checkpoint = auction.checkpoint();
        if ($maxPrice > checkpoint.clearingPrice) {
            auction.exitBid(bidId);
        } else {
            auction.exitPartiallyFilledBid(bidId, 1, 0);
        }

        // Go back to before the claim block
        vm.roll(auction.claimBlock() - 1);

        // Try to claim tokens before the claim block
        vm.expectRevert(IAuction.NotClaimable.selector);
        auction.claimTokens(bidId);
    }

    function test_claimTokens_tokenTransferFails_reverts(uint128 _bidAmount, uint128 _maxPrice)
        public
        givenValidMaxPrice(_maxPrice, TOTAL_SUPPLY)
        givenValidBidAmount(_bidAmount)
        givenGraduatedAuction
        givenFullyFundedAccount
    {
        Auction failingAuction = helper__deployAuctionWithFailingToken();

        uint256 bidId = failingAuction.submitBid{value: $bidAmount}(
            $maxPrice, $bidAmount, alice, tickNumberToPriceX96(1), bytes('')
        );

        vm.roll(auction.endBlock() + 1);
        Checkpoint memory checkpoint = failingAuction.checkpoint();
        if ($maxPrice > checkpoint.clearingPrice) {
            failingAuction.exitBid(bidId);
        } else {
            failingAuction.exitPartiallyFilledBid(bidId, 1, 0);
        }

        uint256 expectedTokensFilled = failingAuction.bids(bidId).tokensFilled;
        vm.assume(expectedTokensFilled > 0);

        vm.roll(failingAuction.claimBlock());

        vm.expectRevert(CurrencyLibrary.ERC20TransferFailed.selector);
        failingAuction.claimTokens(bidId);
    }

    function test_claimTokensBatch_notSameOwner_reverts() public givenFullyFundedAccount {
        uint256 bidId0 = helper__submitBid(auction, alice, TOTAL_SUPPLY - 1, tickNumberToPriceX96(2));
        uint256 bidId1 = helper__submitBid(auction, bob, TOTAL_SUPPLY - 1, tickNumberToPriceX96(2));

        vm.roll(auction.endBlock());
        auction.exitBid(bidId0);
        auction.exitBid(bidId1);

        uint256[] memory bids = new uint256[](2);
        bids[0] = bidId0;
        bids[1] = bidId1;

        vm.roll(auction.claimBlock());
        vm.expectRevert(abi.encodeWithSelector(IAuction.BatchClaimDifferentOwner.selector, alice, bob));
        auction.claimTokensBatch(alice, bids);
    }

    /// forge-config: default.fuzz.runs = 1000
    /// forge-config: ci.fuzz.runs = 1000
    function test_claimTokensBatch_beforeBidExited_reverts(
        uint128 _bidAmount,
        uint128 _numberOfBids,
        uint256 _maxPrice
    )
        public
        givenValidMaxPrice(_maxPrice, TOTAL_SUPPLY)
        givenValidBidAmount(_bidAmount)
        givenGraduatedAuction
        givenFullyFundedAccount
    {
        _numberOfBids = uint128(bound(_numberOfBids, 1, 10));
        uint256[] memory bids = helper__submitNBids(auction, alice, $bidAmount, _numberOfBids, $maxPrice);

        vm.roll(auction.claimBlock());
        vm.expectRevert(IAuction.BidNotExited.selector);
        auction.claimTokensBatch(alice, bids);
    }

    /// forge-config: default.fuzz.runs = 1000
    /// forge-config: ci.fuzz.runs = 1000
    function test_claimTokensBatch_beforeClaimBlock_reverts(
        uint128 _bidAmount,
        uint128 _numberOfBids,
        uint256 _maxPrice
    )
        public
        givenValidMaxPrice(_maxPrice, TOTAL_SUPPLY)
        givenValidBidAmount(_bidAmount)
        givenGraduatedAuction
        givenFullyFundedAccount
    {
        _numberOfBids = uint128(bound(_numberOfBids, 1, 10));
        vm.assume($maxPrice < (uint256(type(uint128).max) * FixedPoint96.Q96) / (TOTAL_SUPPLY + _numberOfBids));
        $bidAmount = uint128(
            _bound(
                $bidAmount, (TOTAL_SUPPLY + _numberOfBids).fullMulDivUp($maxPrice, FixedPoint96.Q96), type(uint128).max
            )
        );

        uint256[] memory bids = helper__submitNBids(auction, alice, $bidAmount, _numberOfBids, $maxPrice);

        vm.roll(auction.endBlock());
        Checkpoint memory checkpoint = auction.checkpoint();
        for (uint256 i = 0; i < _numberOfBids; i++) {
            if ($maxPrice > checkpoint.clearingPrice) {
                auction.exitBid(bids[i]);
            } else {
                auction.exitPartiallyFilledBid(bids[i], 1, 0);
            }
        }

        vm.roll(auction.claimBlock() - 1);
        vm.expectRevert(IAuction.NotClaimable.selector);
        auction.claimTokensBatch(alice, bids);
    }

    /// forge-config: default.fuzz.runs = 1000
    /// forge-config: ci.fuzz.runs = 1000
    function test_claimTokensBatch_tokenTransferFails_reverts(
        uint128 _bidAmount,
        uint128 _numberOfBids,
        uint256 _maxPrice
    )
        public
        givenValidMaxPrice(_maxPrice, TOTAL_SUPPLY)
        givenValidBidAmount(_bidAmount)
        givenGraduatedAuction
        givenFullyFundedAccount
    {
        _numberOfBids = uint128(bound(_numberOfBids, 1, 10));
        vm.assume($maxPrice < (uint256(type(uint128).max) * FixedPoint96.Q96) / (TOTAL_SUPPLY + _numberOfBids));
        $bidAmount = uint128(
            _bound(
                $bidAmount, (TOTAL_SUPPLY + _numberOfBids).fullMulDivUp($maxPrice, FixedPoint96.Q96), type(uint128).max
            )
        );

        Auction failingAuction = helper__deployAuctionWithFailingToken();

        uint256[] memory bids = helper__submitNBids(failingAuction, alice, $bidAmount, _numberOfBids, $maxPrice);

        vm.roll(failingAuction.endBlock() + 1);
        Checkpoint memory checkpoint = failingAuction.checkpoint();
        for (uint256 i = 0; i < _numberOfBids; i++) {
            if ($maxPrice > checkpoint.clearingPrice) {
                failingAuction.exitBid(bids[i]);
            } else {
                failingAuction.exitPartiallyFilledBid(bids[i], 1, 0);
            }
        }

        vm.roll(failingAuction.claimBlock());
        vm.expectRevert(CurrencyLibrary.ERC20TransferFailed.selector);
        failingAuction.claimTokensBatch(alice, bids);
    }

    /// forge-config: default.fuzz.runs = 1000
    /// forge-config: ci.fuzz.runs = 1000
    function test_claimTokensBatch_succeeds(uint128 _bidAmount, uint128 _numberOfBids, uint256 _maxPrice)
        public
        givenValidMaxPrice(_maxPrice, TOTAL_SUPPLY)
        givenValidBidAmount(_bidAmount)
        givenGraduatedAuction
        givenFullyFundedAccount
    {
        _numberOfBids = uint128(bound(_numberOfBids, 1, 10));
        // Because each bid will be a little less due to rounding
        vm.assume($maxPrice < (uint256(type(uint128).max) * FixedPoint96.Q96) / (TOTAL_SUPPLY + _numberOfBids));
        $bidAmount = uint128(
            _bound(
                $bidAmount, (TOTAL_SUPPLY + _numberOfBids).fullMulDivUp($maxPrice, FixedPoint96.Q96), type(uint128).max
            )
        );

        uint256[] memory bids = helper__submitNBids(auction, alice, $bidAmount, _numberOfBids, $maxPrice);

        vm.roll(auction.endBlock());
        Checkpoint memory checkpoint = auction.checkpoint();
        for (uint256 i = 0; i < _numberOfBids; i++) {
            if ($maxPrice > checkpoint.clearingPrice) {
                auction.exitBid(bids[i]);
            } else {
                auction.exitPartiallyFilledBid(bids[i], 1, 0);
            }
        }

        // All bids should clear the same number of tokens
        Bid memory bid = auction.bids(bids[0]);
        uint256 amountClearedPerBid = bid.tokensFilled;

        vm.roll(auction.claimBlock());
        vm.expectEmit(true, true, true, true);
        for (uint256 i = 0; i < _numberOfBids; i++) {
            emit IAuction.TokensClaimed(bids[i], alice, amountClearedPerBid);
        }
        auction.claimTokensBatch(alice, bids);

        assertEq(token.balanceOf(alice), amountClearedPerBid * _numberOfBids);
    }

    function test_sweepCurrency_beforeAuctionEnds_reverts() public {
        vm.startPrank(auction.fundsRecipient());
        vm.roll(auction.endBlock() - 1);
        vm.expectRevert(IAuction.AuctionIsNotOver.selector);
        auction.sweepCurrency();
        vm.stopPrank();
    }

    function test_sweepUnsoldTokens_beforeAuctionEnds_reverts() public {
        vm.roll(auction.endBlock() - 1);
        vm.expectRevert(IAuction.AuctionIsNotOver.selector);
        auction.sweepUnsoldTokens();
    }

    // sweepCurrency tests

    function test_sweepCurrency_alreadySwept_reverts() public {
        // Submit a bid to ensure auction graduates
        auction.submitBid{value: inputAmountForTokens(TOTAL_SUPPLY, tickNumberToPriceX96(2))}(
            tickNumberToPriceX96(2),
            inputAmountForTokens(TOTAL_SUPPLY, tickNumberToPriceX96(2)),
            alice,
            tickNumberToPriceX96(1),
            bytes('')
        );

        vm.roll(auction.endBlock());

        // First sweep should succeed
        vm.prank(auction.fundsRecipient());
        auction.sweepCurrency();

        // Second sweep should fail
        vm.prank(auction.fundsRecipient());
        vm.expectRevert(ITokenCurrencyStorage.CannotSweepCurrency.selector);
        auction.sweepCurrency();
    }

    // sweepUnsoldTokens tests

    function test_sweepUnsoldTokens_alreadySwept_reverts() public {
        vm.roll(auction.endBlock());

        // First sweep should succeed
        auction.sweepUnsoldTokens();

        // Second sweep should fail
        vm.expectRevert(ITokenCurrencyStorage.CannotSweepTokens.selector);
        auction.sweepUnsoldTokens();
    }

    // Test that all of the state getters for constants / immutable variables are correct
    function test_constructor_immutable_getters() public {
        assertEq(Currency.unwrap(auction.currency()), ETH_SENTINEL);
        assertEq(address(auction.token()), address(token));
        assertEq(auction.totalSupply(), TOTAL_SUPPLY);
        assertEq(auction.tokensRecipient(), tokensRecipient);
        assertEq(auction.fundsRecipient(), fundsRecipient);
        assertEq(auction.tickSpacing(), TICK_SPACING);
        assertEq(address(auction.validationHook()), address(0));
        assertEq(auction.floorPrice(), FLOOR_PRICE);
    }

    /// @dev Reproduces rounding error caused by rounding up bid
    function test_repro_rounding_error_tokens_sold_without_moving_clearing_price() public {
        uint256 AUCTION_DURATION = 20;
        uint128 TOTAL_SUPPLY = 1000e18;
        uint256 FLOOR_PRICE = (25 << FixedPoint96.RESOLUTION) / 1_000_000;
        uint256 TICK_SPACING = FLOOR_PRICE;

        AuctionParameters memory params = AuctionParameters({
            currency: address(0),
            floorPrice: FLOOR_PRICE,
            tickSpacing: TICK_SPACING,
            validationHook: address(0),
            fundsRecipient: msg.sender,
            tokensRecipient: msg.sender,
            startBlock: uint64(block.number + 1),
            endBlock: uint64(block.number + 1 + AUCTION_DURATION),
            claimBlock: uint64(block.number + 1 + AUCTION_DURATION),
            requiredCurrencyRaised: 0,
            auctionStepsData: abi.encodePacked(
                uint24(0),
                uint40(1), // 0% for 1 blocks
                abi.encodePacked(
                    uint24(1000e3),
                    uint40(1), // 10% for 1 block
                    abi.encodePacked(uint24(500e3), uint40(18)) // 5% for 18 blocks
                )
            )
        });

        auction = new Auction(address(token), TOTAL_SUPPLY, params);
        token.mint(address(auction), TOTAL_SUPPLY);
        auction.onTokensReceived();

        vm.roll(params.startBlock + 1);

        uint256 maxPrice = FLOOR_PRICE;
        maxPrice += TICK_SPACING; // Increase the maxPrice by FLOOR_PRICE on every iteration
        uint256 lastTickPrice = FLOOR_PRICE;

        // purchase all the tokens
        uint128 amount = inputAmountForTokens(TOTAL_SUPPLY, maxPrice);

        uint256 bidId = auction.submitBid{value: amount, gas: 1_000_000}(
            maxPrice, // maxPrice
            amount, // amount
            alice, // owner
            lastTickPrice, // previousPrice
            '' // hookData
        );

        vm.roll(block.number + 1);
        auction.checkpoint();

        // Advance to the end of the auction
        vm.roll(auction.endBlock() + 1);

        // Exit the bids and claim ATP
        auction.exitPartiallyFilledBid(bidId, 3, 0);
        auction.claimTokens(bidId);
    }

    /// Super large tick spacing
    /// Bids sufficiently large become unable to clear
    // TODO(ez): fix this test to work with new uint128 bids
    function xtest_disallow_bids_too_large_to_clear(uint128 totalSupply) public {
        vm.assume(totalSupply > 0);

        vm.deal(address(this), type(uint256).max);
        uint256 floorPrice = 2;
        uint256 tickSpacing = 1;
        params = params.withFloorPrice(floorPrice).withTickSpacing(tickSpacing);
        auction = new Auction(address(token), totalSupply, params);
        token.mint(address(auction), totalSupply);
        auction.onTokensReceived();

        // Under X7X7 because it will trigger BidAmountTooLarge
        uint128 underMaxAmount = type(uint128).max;
        auction.submitBid{value: underMaxAmount}(3, underMaxAmount, alice, 2, '');

        // Now submit another one that will push it over the limit
        vm.expectRevert(IAuction.InvalidBidUnableToClear.selector);
        auction.submitBid{value: underMaxAmount}(3, underMaxAmount, alice, 2, '');

        vm.roll(block.number + 1);
        // Expect that we can call checkpoint
        auction.checkpoint();
    }

    function logAmountWithDecimal(string memory key, uint256 amount) internal {
        emit log_named_decimal_uint(key, amount, 18);
    }

    function logQ96AmountWithDecimal(string memory key, uint256 amount) internal {
        emit log_named_decimal_uint(key, ((amount * 1e18) >> FixedPoint96.RESOLUTION), 18);
    }
}
