// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Auction, AuctionParameters} from '../src/Auction.sol';
import {IAuction} from '../src/interfaces/IAuction.sol';

import {IAuctionStepStorage} from '../src/interfaces/IAuctionStepStorage.sol';
import {ITickStorage} from '../src/interfaces/ITickStorage.sol';

import {AuctionStepLib} from '../src/libraries/AuctionStepLib.sol';
import {Currency, CurrencyLibrary} from '../src/libraries/CurrencyLibrary.sol';
import {FixedPoint96} from '../src/libraries/FixedPoint96.sol';
import {AuctionParamsBuilder} from './utils/AuctionParamsBuilder.sol';
import {AuctionStepsBuilder} from './utils/AuctionStepsBuilder.sol';

import {MockAuction} from './utils/MockAuction.sol';

import {MockToken} from './utils/MockToken.sol';
import {MockValidationHook} from './utils/MockValidationHook.sol';
import {TokenHandler} from './utils/TokenHandler.sol';

import {Test} from 'forge-std/Test.sol';
import {FixedPointMathLib} from 'solady/utils/FixedPointMathLib.sol';
import {SafeTransferLib} from 'solady/utils/SafeTransferLib.sol';

import {AuctionBaseTest} from './utils/AuctionBaseTest.sol';

contract AuctionTest is AuctionBaseTest {
    using FixedPointMathLib for uint256;
    using AuctionParamsBuilder for AuctionParameters;
    using AuctionStepsBuilder for bytes;

    function setUp() public {
        setUpAuction();
    }

    /// Return the inputAmount required to purchase at least the given number of tokens at the given maxPrice
    function inputAmountForTokens(uint256 tokens, uint256 maxPrice) internal pure returns (uint256) {
        return tokens.fullMulDivUp(maxPrice, FixedPoint96.Q96);
    }

    /// forge-config: default.isolate = true
    /// forge-config: ci.isolate = true
    function test_submitBid_exactIn_succeeds_gas() public {
        vm.expectEmit(true, true, true, true);
        emit IAuction.BidSubmitted(
            0, alice, tickNumberToPriceX96(2), true, inputAmountForTokens(100e18, tickNumberToPriceX96(2))
        );
        auction.submitBid{value: inputAmountForTokens(100e18, tickNumberToPriceX96(2))}(
            tickNumberToPriceX96(2),
            true,
            inputAmountForTokens(100e18, tickNumberToPriceX96(2)),
            alice,
            tickNumberToPriceX96(1),
            bytes('')
        );
        vm.snapshotGasLastCall('submitBid_recordStep_updateCheckpoint');

        vm.roll(block.number + 1);
        auction.submitBid{value: inputAmountForTokens(100e18, tickNumberToPriceX96(2))}(
            tickNumberToPriceX96(2),
            true,
            inputAmountForTokens(100e18, tickNumberToPriceX96(2)),
            alice,
            tickNumberToPriceX96(1),
            bytes('')
        );
        vm.snapshotGasLastCall('submitBid_updateCheckpoint');

        auction.submitBid{value: inputAmountForTokens(100e18, tickNumberToPriceX96(2))}(
            tickNumberToPriceX96(2),
            true,
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
            0, alice, tickNumberToPriceX96(2), true, inputAmountForTokens(TOTAL_SUPPLY, tickNumberToPriceX96(2))
        );
        auction.submitBid{value: inputAmountForTokens(TOTAL_SUPPLY, tickNumberToPriceX96(2))}(
            tickNumberToPriceX96(2),
            true,
            inputAmountForTokens(TOTAL_SUPPLY, tickNumberToPriceX96(2)),
            alice,
            tickNumberToPriceX96(1),
            bytes('')
        );
        vm.snapshotGasLastCall('submitBid_recordStep_updateCheckpoint_initializeTick');

        vm.roll(block.number + 1);
        uint256 expectedTotalCleared = 10e18; // 100e3 mps * total supply (1000e18)
        uint24 expectedCumulativeMps = 100e3; // 100e3 mps * 1 block
        vm.expectEmit(true, true, true, true);
        emit IAuction.CheckpointUpdated(
            block.number, tickNumberToPriceX96(2), expectedTotalCleared, expectedCumulativeMps
        );
        auction.checkpoint();

        assertEq(auction.clearingPrice(), tickNumberToPriceX96(2));
    }

    function test_submitBid_exactOut_initializesTickAndUpdatesClearingPrice_succeeds() public {
        vm.expectEmit(true, true, true, true);
        emit IAuction.BidSubmitted(0, alice, tickNumberToPriceX96(2), false, 1000e18);
        // Oversubscribe the auction to increase the clearing price
        auction.submitBid{value: inputAmountForTokens(1000e18, tickNumberToPriceX96(2))}(
            tickNumberToPriceX96(2), false, 1000e18, alice, tickNumberToPriceX96(1), bytes('')
        );

        vm.roll(block.number + 1);
        uint256 expectedTotalCleared = 10e18; // 100e3 mps * total supply (1000e18)
        uint24 expectedCumulativeMps = 100e3; // 100e3 mps * 1 block
        vm.expectEmit(true, true, true, true);
        emit IAuction.CheckpointUpdated(
            block.number, tickNumberToPriceX96(2), expectedTotalCleared, expectedCumulativeMps
        );
        auction.checkpoint();

        assertEq(auction.clearingPrice(), tickNumberToPriceX96(2));
    }

    function test_submitBid_updatesClearingPrice_succeeds() public {
        vm.expectEmit(true, true, true, true);
        // Expect the checkpoint to be made for the previous block
        emit IAuction.CheckpointUpdated(block.number, tickNumberToPriceX96(1), 0, 0);
        // Bid enough to purchase the entire supply (1000e18) at a higher price (2e18)
        auction.submitBid{value: inputAmountForTokens(TOTAL_SUPPLY, tickNumberToPriceX96(2))}(
            tickNumberToPriceX96(2),
            true,
            inputAmountForTokens(TOTAL_SUPPLY, tickNumberToPriceX96(2)),
            alice,
            tickNumberToPriceX96(1),
            bytes('')
        );

        vm.roll(block.number + 1);
        uint24 expectedCumulativeMps = 100e3; // 100e3 mps * 1 block
        uint256 expectedTotalCleared = 10e18; // 100e3 mps * total supply (1000e18)
        vm.expectEmit(true, true, true, true);
        emit IAuction.CheckpointUpdated(
            block.number, tickNumberToPriceX96(2), expectedTotalCleared, expectedCumulativeMps
        );
        auction.checkpoint();
    }

    function test_submitBid_multipleTicks_succeeds() public {
        uint256 expectedTotalCleared = 100e3 * TOTAL_SUPPLY / AuctionStepLib.MPS;
        uint24 expectedCumulativeMps = 100e3; // 100e3 mps * 1 block

        vm.expectEmit(true, true, true, true);
        // First checkpoint is blank
        emit IAuction.CheckpointUpdated(block.number, tickNumberToPriceX96(1), 0, 0);
        vm.expectEmit(true, true, true, true);
        emit ITickStorage.TickInitialized(tickNumberToPriceX96(2));

        // Bid to purchase 500e18 tokens at a price of 2e6
        auction.submitBid{value: inputAmountForTokens(500e18, tickNumberToPriceX96(2))}(
            tickNumberToPriceX96(2),
            true,
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
            true,
            inputAmountForTokens(501e18, tickNumberToPriceX96(3)),
            alice,
            tickNumberToPriceX96(2),
            bytes('')
        );

        vm.roll(block.number + 1);
        // New block, expect the clearing price to be updated and one block's worth of mps to be sold
        vm.expectEmit(true, true, true, true);
        emit IAuction.CheckpointUpdated(
            block.number, tickNumberToPriceX96(2), expectedTotalCleared, expectedCumulativeMps
        );
        auction.checkpoint();
    }

    function test_submitBid_exactIn_overTotalSupply_isPartiallyFilled() public {
        uint256 inputAmount = inputAmountForTokens(2000e18, tickNumberToPriceX96(2));
        uint256 bidId = auction.submitBid{value: inputAmount}(
            tickNumberToPriceX96(2), true, inputAmount, alice, tickNumberToPriceX96(1), bytes('')
        );

        vm.roll(block.number + 1);
        auction.checkpoint();

        vm.roll(auction.endBlock());
        uint256 aliceBalanceBefore = address(alice).balance;
        uint256 aliceTokenBalanceBefore = token.balanceOf(address(alice));

        auction.exitPartiallyFilledBid(bidId, 2);
        assertEq(address(alice).balance, aliceBalanceBefore + inputAmount / 2);

        auction.claimTokens(bidId);
        assertEq(token.balanceOf(address(alice)), aliceTokenBalanceBefore + 1000e18);
    }

    function test_submitBid_exactOut_overTotalSupply_isPartiallyFilled() public {
        uint256 bidId = auction.submitBid{value: inputAmountForTokens(2000e18, tickNumberToPriceX96(2))}(
            tickNumberToPriceX96(2), false, 2000e18, alice, tickNumberToPriceX96(1), bytes('')
        );

        vm.roll(block.number + 1);
        auction.checkpoint();

        vm.roll(auction.endBlock());
        uint256 aliceBalanceBefore = address(alice).balance;
        uint256 aliceTokenBalanceBefore = token.balanceOf(address(alice));

        auction.exitPartiallyFilledBid(bidId, 2);
        assertEq(
            address(alice).balance, aliceBalanceBefore + inputAmountForTokens(2000e18, tickNumberToPriceX96(2)) / 2
        );

        auction.claimTokens(bidId);
        assertEq(token.balanceOf(address(alice)), aliceTokenBalanceBefore + 1000e18);
    }

    function test_checkpoint_startBlock_succeeds() public {
        vm.roll(auction.startBlock());
        auction.checkpoint();
    }

    function test_checkpoint_endBlock_succeeds() public {
        vm.roll(auction.endBlock());
        auction.checkpoint();
    }

    function test_checkpoint_afterEndBlock_reverts() public {
        vm.roll(auction.endBlock() + 1);
        vm.expectRevert(IAuctionStepStorage.AuctionIsOver.selector);
        auction.checkpoint();
    }

    function test_submitBid_exactIn_atFloorPrice_reverts() public {
        vm.expectRevert(ITickStorage.TickPriceNotIncreasing.selector);
        auction.submitBid{value: inputAmountForTokens(10e18, tickNumberToPriceX96(1))}(
            tickNumberToPriceX96(1),
            true,
            inputAmountForTokens(10e18, tickNumberToPriceX96(1)),
            alice,
            tickNumberToPriceX96(1),
            bytes('')
        );
    }

    function test_submitBid_exactOut_atFloorPrice_reverts() public {
        vm.expectRevert(ITickStorage.TickPriceNotIncreasing.selector);
        auction.submitBid{value: inputAmountForTokens(10e18, tickNumberToPriceX96(1))}(
            tickNumberToPriceX96(1), false, 10e18, alice, tickNumberToPriceX96(1), bytes('')
        );
    }

    function test_submitBid_exactInMsgValue_revertsWithInvalidAmount() public {
        vm.expectRevert(IAuction.InvalidAmount.selector);
        // msg.value should be 1000e18
        auction.submitBid{value: 2000e18}(
            tickNumberToPriceX96(2), true, 1000e18, alice, tickNumberToPriceX96(1), bytes('')
        );
    }

    function test_submitBid_exactInZeroMsgValue_revertsWithInvalidAmount() public {
        vm.expectRevert(IAuction.InvalidAmount.selector);
        auction.submitBid{value: 0}(tickNumberToPriceX96(2), true, 1000e18, alice, tickNumberToPriceX96(1), bytes(''));
    }

    function test_submitBid_exactOutMsgValue_revertsWithInvalidAmount() public {
        vm.expectRevert(IAuction.InvalidAmount.selector);
        // msg.value should be 2 * 1000e18
        auction.submitBid{value: 1000e18}(
            tickNumberToPriceX96(2), false, 1000e18, alice, tickNumberToPriceX96(1), bytes('')
        );
    }

    function test_submitBid_exactInZeroAmount_revertsWithInvalidAmount() public {
        vm.expectRevert(IAuction.InvalidAmount.selector);
        auction.submitBid{value: 1000e18}(tickNumberToPriceX96(2), true, 0, alice, tickNumberToPriceX96(1), bytes(''));
    }

    function test_submitBid_exactOutZeroAmount_revertsWithInvalidAmount() public {
        vm.expectRevert(IAuction.InvalidAmount.selector);
        auction.submitBid{value: 1000e18}(tickNumberToPriceX96(2), false, 0, alice, tickNumberToPriceX96(1), bytes(''));
    }

    function test_submitBid_endBlock_reverts() public {
        vm.roll(auction.endBlock());
        vm.expectRevert(IAuctionStepStorage.AuctionIsOver.selector);
        auction.submitBid{value: 1000e18}(tickNumberToPriceX96(2), true, 1000e18, alice, 1, bytes(''));
    }

    /// forge-config: default.isolate = true
    /// forge-config: ci.isolate = true
    function test_exitBid_succeeds_gas() public {
        uint256 smallAmount = 500e18;
        vm.expectEmit(true, true, true, true);
        emit IAuction.BidSubmitted(
            0, alice, tickNumberToPriceX96(2), true, inputAmountForTokens(smallAmount, tickNumberToPriceX96(2))
        );
        uint256 bidId1 = auction.submitBid{value: inputAmountForTokens(smallAmount, tickNumberToPriceX96(2))}(
            tickNumberToPriceX96(2),
            true,
            inputAmountForTokens(smallAmount, tickNumberToPriceX96(2)),
            alice,
            tickNumberToPriceX96(1),
            bytes('')
        );

        // Bid enough tokens to move the clearing price to 3
        uint256 largeAmount = 1000e18;
        vm.expectEmit(true, true, true, true);
        emit IAuction.BidSubmitted(
            1, alice, tickNumberToPriceX96(3), true, inputAmountForTokens(largeAmount, tickNumberToPriceX96(3))
        );
        uint256 bidId2 = auction.submitBid{value: inputAmountForTokens(largeAmount, tickNumberToPriceX96(3))}(
            tickNumberToPriceX96(3),
            true,
            inputAmountForTokens(largeAmount, tickNumberToPriceX96(3)),
            alice,
            tickNumberToPriceX96(2),
            bytes('')
        );
        uint256 expectedTotalCleared = TOTAL_SUPPLY * 100e3 / AuctionStepLib.MPS;

        vm.roll(block.number + 1);
        vm.expectEmit(true, true, true, true);
        emit IAuction.CheckpointUpdated(block.number, tickNumberToPriceX96(3), expectedTotalCleared, 100e3);
        auction.checkpoint();

        uint256 aliceBalanceBefore = address(alice).balance;
        // Expect that the first bid can be exited, since the clearing price is now above its max price
        vm.expectEmit(true, true, true, true);
        emit IAuction.BidExited(0, alice);
        vm.startPrank(alice);
        auction.exitPartiallyFilledBid(bidId1, 2);
        // Expect that alice is refunded the full amount of the first bid
        assertEq(
            address(alice).balance - aliceBalanceBefore, inputAmountForTokens(smallAmount, tickNumberToPriceX96(2))
        );

        // Expect that the second bid cannot be withdrawn, since the clearing price is below its max price
        vm.expectRevert(IAuction.CannotExitBid.selector);
        auction.exitBid(bidId2);
        vm.stopPrank();
    }

    function test_exitBid_exactOut_succeeds() public {
        uint256 amount = 500e18;
        uint256 maxPrice = tickNumberToPriceX96(2);
        uint256 bidId = auction.submitBid{value: inputAmountForTokens(500e18, tickNumberToPriceX96(2))}(
            maxPrice, false, 500e18, alice, tickNumberToPriceX96(1), bytes('')
        );

        vm.roll(block.number + 1);
        auction.checkpoint();

        // Expect the bid to be above clearing price
        assertGt(maxPrice, auction.clearingPrice());

        uint256 aliceBalanceBefore = address(alice).balance;
        uint256 aliceTokenBalanceBefore = token.balanceOf(address(alice));

        vm.roll(auction.endBlock() + 1);
        auction.exitBid(bidId);
        // Alice initially deposited 500e18 * tickNumberToPrice(2e6) = 1000e24 ETH
        // They only purchased 500e18 tokens at a price of 1e6, so they should be refunded 1000e24 - 500e18 * tickNumberToPrice(1e6) = 500e18 ETH
        assertEq(
            address(alice).balance,
            aliceBalanceBefore + inputAmountForTokens(500e18, tickNumberToPriceX96(2))
                - inputAmountForTokens(500e18, tickNumberToPriceX96(1))
        );

        auction.claimTokens(bidId);
        // Expect fully filled for all tokens
        assertEq(token.balanceOf(address(alice)), aliceTokenBalanceBefore + amount);
    }

    function test_exitBid_afterEndBlock_succeeds() public {
        // Bid at 3 but only provide 1000e18 ETH, such that the auction is only fully filled at 1e6
        uint256 bidId = auction.submitBid{value: inputAmountForTokens(1000e18, tickNumberToPriceX96(1))}(
            tickNumberToPriceX96(3),
            true,
            inputAmountForTokens(1000e18, tickNumberToPriceX96(1)),
            alice,
            tickNumberToPriceX96(1),
            bytes('')
        );

        vm.roll(block.number + 1);
        vm.expectEmit(true, true, true, true);
        emit IAuction.CheckpointUpdated(
            block.number, tickNumberToPriceX96(1), TOTAL_SUPPLY * 100e3 / AuctionStepLib.MPS, 100e3
        );
        auction.checkpoint();

        // Before the auction ends, the bid should not be exitable since it is above the clearing price
        vm.startPrank(alice);
        vm.roll(auction.endBlock() - 1);
        vm.expectRevert(IAuction.CannotExitBid.selector);
        auction.exitBid(bidId);

        uint256 aliceBalanceBefore = address(alice).balance;

        // Now that the auction has ended, the bid should be exitable
        vm.roll(auction.endBlock());
        auction.exitBid(bidId);
        // Expect no refund
        assertEq(address(alice).balance, aliceBalanceBefore);
        auction.claimTokens(bidId);
        // Expect purchased 1000e18 tokens
        assertEq(token.balanceOf(address(alice)), 1000e18);
        vm.stopPrank();
    }

    function test_exitBid_joinedLate_succeeds() public {
        vm.roll(auction.endBlock() - 1);
        // Bid at 2 but only provide 1000e18 ETH, such that the auction is only fully filled at 1e6
        uint256 bidId = auction.submitBid{value: inputAmountForTokens(1000e18, tickNumberToPriceX96(1))}(
            tickNumberToPriceX96(2),
            true,
            inputAmountForTokens(1000e18, tickNumberToPriceX96(1)),
            alice,
            tickNumberToPriceX96(1),
            bytes('')
        );

        uint256 aliceBalanceBefore = address(alice).balance;
        uint256 aliceTokenBalanceBefore = token.balanceOf(address(alice));
        vm.roll(auction.endBlock() + 1);
        auction.exitBid(bidId);
        // Expect no refund since the bid was fully exited
        assertEq(address(alice).balance, aliceBalanceBefore);
        auction.claimTokens(bidId);
        assertEq(token.balanceOf(address(alice)), aliceTokenBalanceBefore + 1000e18);
    }

    function test_exitBid_beforeEndBlock_revertsWithCannotExitBid() public {
        uint256 bidId = auction.submitBid{value: inputAmountForTokens(1000e18, tickNumberToPriceX96(3))}(
            tickNumberToPriceX96(3),
            true,
            inputAmountForTokens(1000e18, tickNumberToPriceX96(3)),
            alice,
            tickNumberToPriceX96(1),
            bytes('')
        );
        // Expect revert because the bid is not below the clearing price
        vm.expectRevert(IAuction.CannotExitBid.selector);
        vm.prank(alice);
        auction.exitBid(bidId);
    }

    function test_exitBid_alreadyExited_revertsWithBidAlreadyExited() public {
        uint256 bidId = auction.submitBid{value: inputAmountForTokens(500e18, tickNumberToPriceX96(3))}(
            tickNumberToPriceX96(3),
            true,
            inputAmountForTokens(500e18, tickNumberToPriceX96(3)),
            alice,
            tickNumberToPriceX96(1),
            bytes('')
        );
        vm.roll(auction.endBlock());

        // The clearing price is at tick 1 which is below our clearing price so we can use `exitBid`
        vm.startPrank(alice);
        auction.exitBid(bidId);
        vm.expectRevert(IAuction.BidAlreadyExited.selector);
        auction.exitBid(bidId);
        vm.stopPrank();
    }

    function test_exitBid_maxPriceAtClearingPrice_revertsWithCannotExitBid() public {
        uint256 bidId = auction.submitBid{value: inputAmountForTokens(1000e18, tickNumberToPriceX96(2))}(
            tickNumberToPriceX96(2),
            true,
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

    /// Simple test for a bid that partially fills at the clearing price but is the only bid at that price, functionally fully filled
    function test_exitPartiallyFilledBid_noOtherBidsAtClearingPrice_succeeds() public {
        uint256 bidId = auction.submitBid{value: inputAmountForTokens(1000e18, tickNumberToPriceX96(2))}(
            tickNumberToPriceX96(2),
            true,
            inputAmountForTokens(1000e18, tickNumberToPriceX96(2)),
            alice,
            tickNumberToPriceX96(1),
            bytes('')
        );
        vm.roll(block.number + 1);
        auction.checkpoint();

        vm.roll(auction.endBlock() - 1);
        vm.expectRevert(IAuction.CannotExitBid.selector);
        vm.prank(alice);
        auction.exitPartiallyFilledBid(bidId, 2);

        uint256 aliceBalanceBefore = address(alice).balance;

        vm.roll(auction.endBlock());
        vm.prank(alice);
        auction.exitPartiallyFilledBid(bidId, 2);

        // Expect no refund
        assertEq(address(alice).balance, aliceBalanceBefore);
    }

    /// forge-config: default.isolate = true
    /// forge-config: ci.isolate = true
    function test_exitPartiallyFilledBid_succeeds_gas() public {
        address bob = makeAddr('bob');
        uint256 bidId = auction.submitBid{value: inputAmountForTokens(500e18, tickNumberToPriceX96(11))}(
            tickNumberToPriceX96(11),
            true,
            inputAmountForTokens(500e18, tickNumberToPriceX96(11)),
            alice,
            tickNumberToPriceX96(1),
            bytes('')
        );
        uint256 bidId2 = auction.submitBid{value: inputAmountForTokens(500e18, tickNumberToPriceX96(21))}(
            tickNumberToPriceX96(21),
            true,
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
        auction.exitPartiallyFilledBid(bidId, 2);
        vm.snapshotGasLastCall('exitPartiallyFilledBid');
        // Alice is purchasing with 500e18 * 2000 = 1000e21 ETH
        // Bob is purchasing with 500e18 * 3000 = 1500e21 ETH
        // At a clearing price of 2e6
        // Since the supply is only 1000e18, that means that bob should fully fill for 750e18 tokens, and
        // Alice should partially fill for 250e18 tokens, spending 500e21 ETH
        // Meaning she should be refunded 1000e21 - 500e21 = 500e21 ETH
        assertEq(address(alice).balance, aliceBalanceBefore + 500e21);
        auction.claimTokens(bidId);
        vm.snapshotGasLastCall('claimTokens');
        assertEq(token.balanceOf(address(alice)), aliceTokenBalanceBefore + 250e18);
        vm.stopPrank();

        vm.startPrank(bob);
        auction.exitBid(bidId2);
        vm.snapshotGasLastCall('exitBid');
        // Bob purchased 750e18 tokens for a price of 2, so they should have spent all of their ETH.
        assertEq(address(bob).balance, bobBalanceBefore + 0);
        auction.claimTokens(bidId2);
        assertEq(token.balanceOf(address(bob)), bobTokenBalanceBefore + 750e18);
        vm.stopPrank();
    }

    function test_exitPartiallyFilledBid_multipleBidders_succeeds() public {
        address bob = makeAddr('bob');
        address charlie = makeAddr('charlie');
        uint256 bidId1 = auction.submitBid{value: inputAmountForTokens(400e18, tickNumberToPriceX96(11))}(
            tickNumberToPriceX96(11),
            true,
            inputAmountForTokens(400e18, tickNumberToPriceX96(11)),
            alice,
            tickNumberToPriceX96(1),
            bytes('')
        );
        uint256 bidId2 = auction.submitBid{value: inputAmountForTokens(600e18, tickNumberToPriceX96(11))}(
            tickNumberToPriceX96(11),
            true,
            inputAmountForTokens(600e18, tickNumberToPriceX96(11)),
            bob,
            tickNumberToPriceX96(1),
            bytes('')
        );

        // Not enough to move the price to 3, but to cause partial fills at 2
        uint256 bidId3 = auction.submitBid{value: inputAmountForTokens(500e18, tickNumberToPriceX96(21))}(
            tickNumberToPriceX96(21),
            true,
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

        // Clearing price is at tick 21 = 2000
        // Alice is purchasing with 400e18 * 2000 = 800e21 ETH
        // Bob is purchasing with 600e18 * 2000 = 1200e21 ETH
        // Charlie is purchasing with 500e18 * 2000 = 1500e21 ETH
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
        vm.roll(auction.endBlock() + 1);

        vm.startPrank(charlie);
        auction.exitBid(bidId3);
        assertEq(address(charlie).balance, charlieBalanceBefore + 0);
        auction.claimTokens(bidId3);
        assertEq(token.balanceOf(address(charlie)), charlieTokenBalanceBefore + 750e18);
        vm.stopPrank();

        vm.startPrank(alice);
        auction.exitPartiallyFilledBid(bidId1, 2);
        assertEq(address(alice).balance, aliceBalanceBefore + 600e21);
        auction.claimTokens(bidId1);
        assertEq(token.balanceOf(address(alice)), aliceTokenBalanceBefore + 100e18);

        vm.startPrank(bob);
        auction.exitPartiallyFilledBid(bidId2, 2);
        assertEq(address(bob).balance, bobBalanceBefore + 900e21);
        auction.claimTokens(bidId2);
        assertEq(token.balanceOf(address(bob)), bobTokenBalanceBefore + 150e18);
        vm.stopPrank();
    }

    function test_onTokensReceived_withCorrectTokenAndAmount_succeeds() public view {
        // Should not revert since tokens are already minted in setUp()
        auction.onTokensReceived(address(token), TOTAL_SUPPLY);
    }

    function test_onTokensReceived_withWrongToken_reverts() public {
        // Create a different token
        address wrongToken = makeAddr('wrongToken');

        vm.expectRevert(IAuction.IDistributionContract__InvalidToken.selector);
        auction.onTokensReceived(wrongToken, TOTAL_SUPPLY);
    }

    function test_onTokensReceived_withWrongAmount_reverts() public {
        vm.expectRevert(IAuction.IDistributionContract__InvalidAmount.selector);
        auction.onTokensReceived(address(token), TOTAL_SUPPLY + 1);
    }

    function test_onTokensReceived_withWrongBalance_reverts() public {
        // Mint less tokens than expected
        token.mint(address(auction), TOTAL_SUPPLY - 1);

        vm.expectRevert(IAuction.IDistributionContract__InvalidAmountReceived.selector);
        auction.onTokensReceived(address(token), TOTAL_SUPPLY);
    }

    function test_advanceToCurrentStep_withClearingPriceZero() public {
        // Create auction with multiple steps
        bytes memory auctionStepsData = AuctionStepsBuilder.init().addStep(100e3, 100);

        AuctionParameters memory params = AuctionParamsBuilder.init().withCurrency(ETH_SENTINEL).withFloorPrice(
            FLOOR_PRICE
        ).withTickSpacing(TICK_SPACING).withValidationHook(address(0)).withTokensRecipient(tokensRecipient)
            .withFundsRecipient(fundsRecipient).withStartBlock(block.number).withEndBlock(block.number + 100).withClaimBlock(
            block.number + 100
        ).withAuctionStepsData(auctionStepsData);

        Auction newAuction = new Auction(address(token), TOTAL_SUPPLY, params);
        token.mint(address(newAuction), TOTAL_SUPPLY);

        // Advance to middle of step without any bids (clearing price = 0)
        vm.roll(block.number + 50);
        newAuction.checkpoint();

        // Should not have transformed checkpoint since clearing price is 0
        // The clearing price will be set to floor price when first checkpoint is created
        assertEq(newAuction.clearingPrice(), FLOOR_PRICE);
    }

    function test_calculateNewClearingPrice_withNoDemand() public {
        // Don't submit any bids
        vm.roll(block.number + 1);
        auction.checkpoint();

        // Clearing price should be the next active tick price since there's no demand
        assertEq(auction.clearingPrice(), auction.nextActiveTickPrice());
    }

    function test_exitPartiallyFilledBid_withInvalidCheckpointHint_reverts() public {
        // Submit a bid at price 2
        uint256 bidId = auction.submitBid{value: inputAmountForTokens(100e18, tickNumberToPriceX96(2))}(
            tickNumberToPriceX96(2),
            true,
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
            true,
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
        vm.expectRevert(IAuction.InvalidCheckpointHint.selector);
        auction.exitPartiallyFilledBid(bidId, 2);
    }

    function test_advanceToCurrentStep_withMultipleStepsAndClearingPrice() public {
        bytes memory auctionStepsData =
            AuctionStepsBuilder.init().addStep(100e3, 20).addStep(150e3, 20).addStep(250e3, 20);

        AuctionParameters memory params = AuctionParamsBuilder.init().withCurrency(ETH_SENTINEL).withFloorPrice(
            FLOOR_PRICE
        ).withTickSpacing(TICK_SPACING).withValidationHook(address(0)).withTokensRecipient(tokensRecipient)
            .withFundsRecipient(fundsRecipient).withStartBlock(block.number).withEndBlock(block.number + 60).withClaimBlock(
            block.number + 60
        ).withAuctionStepsData(auctionStepsData);

        Auction newAuction = new Auction(address(token), TOTAL_SUPPLY, params);
        token.mint(address(newAuction), TOTAL_SUPPLY);

        newAuction.submitBid{value: inputAmountForTokens(100e18, tickNumberToPriceX96(2))}(
            tickNumberToPriceX96(2),
            true,
            inputAmountForTokens(100e18, tickNumberToPriceX96(2)),
            alice,
            tickNumberToPriceX96(1),
            bytes('')
        );

        vm.roll(block.number + 10);
        newAuction.checkpoint();

        vm.roll(block.number + 15);
        newAuction.checkpoint();

        (uint24 mps,,) = newAuction.step();
        assertEq(mps, 150e3);

        vm.roll(block.number + 20);
        newAuction.checkpoint();

        (mps,,) = newAuction.step();
        assertEq(mps, 250e3);
    }

    function test_calculateNewClearingPrice_belowFloorPrice_returnsFloorPrice() public {
        bytes memory auctionStepsData = AuctionStepsBuilder.init().addStep(100e3, 100);

        AuctionParameters memory params = AuctionParamsBuilder.init().withCurrency(ETH_SENTINEL).withFloorPrice(
            10e6 << FixedPoint96.RESOLUTION
        ).withTickSpacing(TICK_SPACING).withValidationHook(address(0)).withTokensRecipient(tokensRecipient)
            .withFundsRecipient(fundsRecipient).withStartBlock(block.number).withEndBlock(block.number + AUCTION_DURATION)
            .withClaimBlock(block.number + AUCTION_DURATION).withAuctionStepsData(auctionStepsData);

        MockAuction mockAuction = new MockAuction(address(token), TOTAL_SUPPLY, params);
        token.mint(address(mockAuction), TOTAL_SUPPLY);

        // Set up the auction state by submitting a bid and checkpointing
        uint256 bidPrice = 12e6 << FixedPoint96.RESOLUTION;
        mockAuction.submitBid{value: inputAmountForTokens(100e18, bidPrice)}(
            bidPrice, true, inputAmountForTokens(100e18, bidPrice), alice, 10e6 << FixedPoint96.RESOLUTION, bytes('')
        );

        vm.roll(block.number + 1);
        mockAuction.checkpoint(); // This sets up sumDemandAboveClearing properly

        // We need: minimumClearingPrice < calculated_price < floorPrice
        // Use a much smaller minimumClearingPrice so the calculated price will be above it
        uint256 minimumClearingPrice = 1e1 << FixedPoint96.RESOLUTION; // Much much smaller than floor price (10e6 << 96)

        // Use a blockTokenSupply that will give a calculated price between minimumClearingPrice and floorPrice
        // The formula is: clearingPrice = currencyDemand * Q96 / (blockTokenSupply - tokenDemand)
        // We want: minimumClearingPrice < calculated_price < floorPrice
        // With currencyDemand = 120e18 and tokenDemand = 100e18, we need to find the right blockTokenSupply
        uint256 blockTokenSupply = 1e22; // Even larger supply to get a smaller calculated price

        uint256 result = mockAuction.calculateNewClearingPrice(
            minimumClearingPrice, // minimumClearingPrice in X96 (below floor price)
            blockTokenSupply // blockTokenSupply
        );

        assertEq(result, 10e6 << FixedPoint96.RESOLUTION);
    }

    function test_submitBid_withValidationHook_callsValidationHook() public {
        // Create a mock validation hook
        MockValidationHook validationHook = new MockValidationHook();

        // Create auction parameters with the validation hook
        bytes memory auctionStepsData = AuctionStepsBuilder.init().addStep(100e3, 100);
        AuctionParameters memory params = AuctionParamsBuilder.init().withCurrency(ETH_SENTINEL).withFloorPrice(
            FLOOR_PRICE
        ).withTickSpacing(TICK_SPACING).withValidationHook(address(validationHook)).withTokensRecipient(tokensRecipient)
            .withFundsRecipient(fundsRecipient).withStartBlock(block.number).withEndBlock(block.number + AUCTION_DURATION)
            .withClaimBlock(block.number + AUCTION_DURATION) // Set the validation hook
            .withAuctionStepsData(auctionStepsData);

        Auction testAuction = new Auction(address(token), TOTAL_SUPPLY, params);
        token.mint(address(testAuction), TOTAL_SUPPLY);

        // Submit a bid with hook data to trigger the validation hook
        uint256 bidId = testAuction.submitBid{value: inputAmountForTokens(100e18, tickNumberToPriceX96(2))}(
            tickNumberToPriceX96(2),
            true,
            inputAmountForTokens(100e18, tickNumberToPriceX96(2)),
            alice,
            tickNumberToPriceX96(1),
            bytes('hook data')
        );

        assertEq(bidId, 0);
    }

    function test_submitBid_withERC20Currency_unpermittedPermit2Transfer_reverts() public {
        // Create auction parameters with ERC20 currency instead of ETH
        bytes memory auctionStepsData = AuctionStepsBuilder.init().addStep(100e3, 100);
        AuctionParameters memory params = AuctionParamsBuilder.init().withCurrency(address(currency)).withFloorPrice(
            FLOOR_PRICE
        ).withTickSpacing(TICK_SPACING).withValidationHook(address(0)).withTokensRecipient(tokensRecipient)
            .withFundsRecipient(fundsRecipient).withStartBlock(block.number).withEndBlock(block.number + AUCTION_DURATION)
            .withClaimBlock(block.number + AUCTION_DURATION) // Use ERC20 currency instead of ETH_SENTINEL
            .withAuctionStepsData(auctionStepsData);

        Auction erc20Auction = new Auction(address(token), TOTAL_SUPPLY, params);
        token.mint(address(erc20Auction), TOTAL_SUPPLY);

        // Mint currency tokens to alice
        currency.mint(alice, 1000e18);

        // For now, let's just verify that the currency is set correctly
        // and that we would reach line 252 if the Permit2 transfer worked
        assertEq(Currency.unwrap(erc20Auction.currency()), address(currency));
        assertFalse(erc20Auction.currency().isAddressZero());

        vm.expectRevert(SafeTransferLib.TransferFromFailed.selector); // Expect revert due to Permit2 transfer failure
        erc20Auction.submitBid{value: 0}(
            tickNumberToPriceX96(2),
            true,
            inputAmountForTokens(100e18, tickNumberToPriceX96(2)),
            alice,
            tickNumberToPriceX96(1),
            bytes('')
        );
    }

    function test_exitPartiallyFilledBid_withInvalidCheckpointHint_atEndBlock_reverts() public {
        uint256 bidId = auction.submitBid{value: inputAmountForTokens(100e18, tickNumberToPriceX96(2))}(
            tickNumberToPriceX96(2),
            true,
            inputAmountForTokens(100e18, tickNumberToPriceX96(2)),
            alice,
            tickNumberToPriceX96(1),
            bytes('')
        );

        vm.roll(block.number + 1);
        auction.checkpoint();

        vm.roll(auction.endBlock() + 1);

        vm.expectRevert(IAuction.InvalidCheckpointHint.selector);
        auction.exitPartiallyFilledBid(bidId, 2);
    }

    function test_auctionConstruction_reverts() public {
        bytes memory auctionStepsData = AuctionStepsBuilder.init().addStep(100e3, 100);
        AuctionParameters memory params = AuctionParamsBuilder.init().withCurrency(ETH_SENTINEL).withFloorPrice(
            FLOOR_PRICE
        ).withTickSpacing(TICK_SPACING).withValidationHook(address(0)).withTokensRecipient(tokensRecipient)
            .withFundsRecipient(fundsRecipient).withStartBlock(block.number).withEndBlock(block.number + AUCTION_DURATION)
            .withClaimBlock(block.number + AUCTION_DURATION).withAuctionStepsData(auctionStepsData);

        vm.expectRevert(IAuction.TotalSupplyIsZero.selector);
        new Auction(address(token), 0, params);

        params = AuctionParamsBuilder.init().withCurrency(ETH_SENTINEL).withFloorPrice(0).withTickSpacing(TICK_SPACING)
            .withValidationHook(address(0)).withTokensRecipient(tokensRecipient).withFundsRecipient(fundsRecipient)
            .withStartBlock(block.number).withEndBlock(block.number + AUCTION_DURATION).withClaimBlock(
            block.number + AUCTION_DURATION
        ).withAuctionStepsData(auctionStepsData);

        vm.expectRevert(IAuction.FloorPriceIsZero.selector);
        new Auction(address(token), TOTAL_SUPPLY, params);

        params = AuctionParamsBuilder.init().withCurrency(ETH_SENTINEL).withFloorPrice(FLOOR_PRICE).withTickSpacing(
            TICK_SPACING
        ).withValidationHook(address(0)).withTokensRecipient(tokensRecipient).withFundsRecipient(fundsRecipient)
            .withStartBlock(block.number).withEndBlock(block.number + AUCTION_DURATION).withClaimBlock(
            block.number + AUCTION_DURATION - 1
        ).withAuctionStepsData(auctionStepsData);

        vm.expectRevert(IAuction.ClaimBlockIsBeforeEndBlock.selector);
        new Auction(address(token), TOTAL_SUPPLY, params);

        params = AuctionParamsBuilder.init().withCurrency(ETH_SENTINEL).withFloorPrice(FLOOR_PRICE).withTickSpacing(
            TICK_SPACING
        ).withValidationHook(address(0)).withTokensRecipient(tokensRecipient).withFundsRecipient(address(0))
            .withStartBlock(block.number).withEndBlock(block.number + AUCTION_DURATION).withClaimBlock(
            block.number + AUCTION_DURATION
        ).withAuctionStepsData(auctionStepsData);

        vm.expectRevert(IAuction.FundsRecipientIsZero.selector);
        new Auction(address(token), TOTAL_SUPPLY, params);
    }

    function test_checkpoint_beforeAuctionStarts_reverts() public {
        // Create an auction that starts in the future
        bytes memory auctionStepsData = AuctionStepsBuilder.init().addStep(100e3, 100);
        AuctionParameters memory params = AuctionParamsBuilder.init().withCurrency(ETH_SENTINEL).withFloorPrice(
            FLOOR_PRICE
        ).withTickSpacing(TICK_SPACING).withValidationHook(address(0)).withTokensRecipient(tokensRecipient)
            .withFundsRecipient(fundsRecipient).withStartBlock(block.number + 10).withEndBlock(
            block.number + 10 + AUCTION_DURATION
        ).withClaimBlock(block.number + 10 + AUCTION_DURATION).withAuctionStepsData(auctionStepsData);

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
            true,
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
            true,
            inputAmountForTokens(500e18, tickNumberToPriceX96(2)),
            alice,
            tickNumberToPriceX96(1),
            bytes('')
        );
        auction.submitBid{value: inputAmountForTokens(500e18, tickNumberToPriceX96(3))}(
            tickNumberToPriceX96(3),
            true,
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
        auction.exitPartiallyFilledBid(bidId, 2);

        // Try to exit the same bid again - this should revert with BidAlreadyExited on line 294
        vm.expectRevert(IAuction.BidAlreadyExited.selector);
        auction.exitPartiallyFilledBid(bidId, 2);

        vm.stopPrank();
    }

    function test_exitPartiallyFilledBid_withInvalidCheckpointHint_onLine308_reverts() public {
        // Submit a bid at a lower price
        uint256 bidId = auction.submitBid{value: inputAmountForTokens(100e18, tickNumberToPriceX96(2))}(
            tickNumberToPriceX96(2),
            true,
            inputAmountForTokens(100e18, tickNumberToPriceX96(2)),
            alice,
            tickNumberToPriceX96(1),
            bytes('')
        );

        // Submit a much larger bid to move the clearing price above the first bid
        auction.submitBid{value: inputAmountForTokens(1000e18, tickNumberToPriceX96(3))}(
            tickNumberToPriceX96(3),
            true,
            inputAmountForTokens(1000e18, tickNumberToPriceX96(3)),
            alice,
            tickNumberToPriceX96(2),
            bytes('')
        );

        vm.roll(block.number + 1);
        auction.checkpoint();

        // Now the clearing price should be above the first bid's max price
        // But we'll try to exit with a checkpoint hint that points to a checkpoint
        // where the clearing price is not strictly greater than the bid's max price
        vm.startPrank(alice);

        // Try to exit with checkpoint 1, which should have clearing price <= bid.maxPrice
        vm.expectRevert(IAuction.InvalidCheckpointHint.selector);
        auction.exitPartiallyFilledBid(bidId, 1);

        vm.stopPrank();
    }

    function test_claimTokens_beforeBidExited_reverts() public {
        // Submit a bid but don't exit it
        uint256 bidId = auction.submitBid{value: inputAmountForTokens(100e18, tickNumberToPriceX96(2))}(
            tickNumberToPriceX96(2),
            true,
            inputAmountForTokens(100e18, tickNumberToPriceX96(2)),
            alice,
            tickNumberToPriceX96(1),
            bytes('')
        );

        // Try to claim tokens before the bid has been exited
        vm.startPrank(alice);
        vm.expectRevert(IAuction.BidNotExited.selector);
        auction.claimTokens(bidId);
        vm.stopPrank();
    }

    function test_claimTokens_beforeClaimBlock_reverts() public {
        uint256 bidId = auction.submitBid{value: inputAmountForTokens(100e18, tickNumberToPriceX96(2))}(
            tickNumberToPriceX96(2),
            true,
            inputAmountForTokens(100e18, tickNumberToPriceX96(2)),
            alice,
            tickNumberToPriceX96(1),
            bytes('')
        );

        // Exit the bid
        vm.roll(auction.endBlock() + 1);
        vm.startPrank(alice);
        auction.exitBid(bidId);

        // Go back to before the claim block
        vm.roll(auction.claimBlock() - 1);

        // Try to claim tokens before the claim block
        vm.expectRevert(IAuction.NotClaimable.selector);
        auction.claimTokens(bidId);
        vm.stopPrank();
    }

    function test_claimTokens_tokenTransferFails_reverts() public {
        MockToken failingToken = new MockToken();

        bytes memory auctionStepsData = AuctionStepsBuilder.init().addStep(100e3, 100);
        AuctionParameters memory params = AuctionParamsBuilder.init().withCurrency(ETH_SENTINEL).withFloorPrice(
            FLOOR_PRICE
        ).withTickSpacing(TICK_SPACING).withValidationHook(address(0)).withTokensRecipient(tokensRecipient)
            .withFundsRecipient(fundsRecipient).withStartBlock(block.number).withEndBlock(block.number + AUCTION_DURATION)
            .withClaimBlock(block.number + AUCTION_DURATION).withAuctionStepsData(auctionStepsData);

        Auction failingAuction = new Auction(address(failingToken), TOTAL_SUPPLY, params);

        failingToken.mint(address(failingAuction), TOTAL_SUPPLY);

        uint256 bidId = failingAuction.submitBid{value: inputAmountForTokens(100e18, tickNumberToPriceX96(2))}(
            tickNumberToPriceX96(2),
            true,
            inputAmountForTokens(100e18, tickNumberToPriceX96(2)),
            alice,
            tickNumberToPriceX96(1),
            bytes('')
        );

        vm.roll(auction.endBlock() + 1);
        vm.startPrank(alice);
        failingAuction.exitBid(bidId);

        vm.roll(failingAuction.claimBlock());

        vm.expectRevert(CurrencyLibrary.ERC20TransferFailed.selector);
        failingAuction.claimTokens(bidId);
        vm.stopPrank();
    }
}
