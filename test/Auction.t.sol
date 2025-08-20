// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Auction, AuctionParameters} from '../src/Auction.sol';
import {IAuction} from '../src/interfaces/IAuction.sol';

import {IAuctionStepStorage} from '../src/interfaces/IAuctionStepStorage.sol';
import {ITickStorage} from '../src/interfaces/ITickStorage.sol';
import {AuctionStepLib} from '../src/libraries/AuctionStepLib.sol';
import {BidLib} from '../src/libraries/BidLib.sol';
import {AuctionParamsBuilder} from './utils/AuctionParamsBuilder.sol';
import {AuctionStepsBuilder} from './utils/AuctionStepsBuilder.sol';
import {TokenHandler} from './utils/TokenHandler.sol';
import {Test} from 'forge-std/Test.sol';

contract AuctionTest is TokenHandler, Test {
    using AuctionParamsBuilder for AuctionParameters;
    using AuctionStepsBuilder for bytes;

    Auction auction;

    uint256 public constant AUCTION_DURATION = 100;
    uint256 public constant TICK_SPACING = 1e6;
    uint128 public constant FLOOR_PRICE = 1e6;
    uint256 public constant TOTAL_SUPPLY = 1000e18;

    address public alice;
    address public tokensRecipient;
    address public fundsRecipient;

    function _tickPriceAt(uint128 id) public pure returns (uint128 price) {
        require(id > 0, 'id must be greater than 0');
        return uint128(FLOOR_PRICE + (id - 1) * TICK_SPACING);
    }

    function setUp() public {
        setUpTokens();

        alice = makeAddr('alice');
        tokensRecipient = makeAddr('tokensRecipient');
        fundsRecipient = makeAddr('fundsRecipient');

        bytes memory auctionStepsData = AuctionStepsBuilder.init().addStep(100e3, 100);
        AuctionParameters memory params = AuctionParamsBuilder.init().withCurrency(ETH_SENTINEL).withFloorPrice(
            FLOOR_PRICE
        ).withTickSpacing(TICK_SPACING).withValidationHook(address(0)).withTokensRecipient(tokensRecipient)
            .withFundsRecipient(fundsRecipient).withStartBlock(block.number).withEndBlock(block.number + AUCTION_DURATION)
            .withClaimBlock(block.number + AUCTION_DURATION).withAuctionStepsData(auctionStepsData);

        // Expect the floor price tick to be initialized
        vm.expectEmit(true, true, true, true);
        emit ITickStorage.TickInitialized(_tickPriceAt(1));
        auction = new Auction(address(token), TOTAL_SUPPLY, params);

        token.mint(address(auction), TOTAL_SUPPLY);
    }

    /// forge-config: default.isolate = true
    /// forge-config: ci.isolate = true
    function test_submitBid_exactIn_succeeds_gas() public {
        vm.expectEmit(true, true, true, true);
        emit IAuction.BidSubmitted(0, alice, _tickPriceAt(2), true, 100e18);
        auction.submitBid{value: 100e18}(_tickPriceAt(2), true, 100e18, alice, 1, bytes(''));
        vm.snapshotGasLastCall('submitBid_recordStep_updateCheckpoint');

        vm.roll(block.number + 1);
        auction.submitBid{value: 100e18}(_tickPriceAt(2), true, 100e18, alice, 1, bytes(''));
        vm.snapshotGasLastCall('submitBid_updateCheckpoint');

        auction.submitBid{value: 100e18}(_tickPriceAt(2), true, 100e18, alice, 1, bytes(''));
        vm.snapshotGasLastCall('submitBid');
    }

    /// forge-config: default.isolate = true
    /// forge-config: ci.isolate = true
    function test_submitBid_exactIn_initializesTickAndUpdatesClearingPrice_succeeds_gas() public {
        vm.expectEmit(true, true, true, true);
        emit IAuction.BidSubmitted(0, alice, _tickPriceAt(2), true, TOTAL_SUPPLY * _tickPriceAt(2));
        auction.submitBid{value: TOTAL_SUPPLY * _tickPriceAt(2)}(
            _tickPriceAt(2), true, TOTAL_SUPPLY * _tickPriceAt(2), alice, 1, bytes('')
        );
        vm.snapshotGasLastCall('submitBid_recordStep_updateCheckpoint_initializeTick');

        vm.roll(block.number + 1);
        uint256 expectedTotalCleared = 10e18; // 100e3 mps * total supply (1000e18)
        uint24 expectedCumulativeMps = 100e3; // 100e3 mps * 1 block
        vm.expectEmit(true, true, true, true);
        emit IAuction.CheckpointUpdated(block.number, _tickPriceAt(2), expectedTotalCleared, expectedCumulativeMps);
        auction.checkpoint();

        assertEq(auction.clearingPrice(), _tickPriceAt(2));
    }

    function test_submitBid_exactOut_initializesTickAndUpdatesClearingPrice_succeeds() public {
        vm.expectEmit(true, true, true, true);
        emit IAuction.BidSubmitted(0, alice, _tickPriceAt(2), false, 1000e18);
        // Oversubscribe the auction to increase the clearing price
        auction.submitBid{value: 1000e18 * _tickPriceAt(2)}(_tickPriceAt(2), false, 1000e18, alice, 1, bytes(''));

        vm.roll(block.number + 1);
        uint256 expectedTotalCleared = 10e18; // 100e3 mps * total supply (1000e18)
        uint24 expectedCumulativeMps = 100e3; // 100e3 mps * 1 block
        vm.expectEmit(true, true, true, true);
        emit IAuction.CheckpointUpdated(block.number, _tickPriceAt(2), expectedTotalCleared, expectedCumulativeMps);
        auction.checkpoint();

        assertEq(auction.clearingPrice(), _tickPriceAt(2));
    }

    function test_submitBid_updatesClearingPrice_succeeds() public {
        vm.expectEmit(true, true, true, true);
        // Expect the checkpoint to be made for the previous block
        emit IAuction.CheckpointUpdated(block.number, _tickPriceAt(1), 0, 0);
        // Bid enough to purchase the entire supply (1000e18) at a higher price (2e18)
        auction.submitBid{value: TOTAL_SUPPLY * _tickPriceAt(2)}(
            _tickPriceAt(2), true, TOTAL_SUPPLY * _tickPriceAt(2), alice, 1, bytes('')
        );

        vm.roll(block.number + 1);
        uint24 expectedCumulativeMps = 100e3; // 100e3 mps * 1 block
        uint256 expectedTotalCleared = 10e18; // 100e3 mps * total supply (1000e18)
        vm.expectEmit(true, true, true, true);
        emit IAuction.CheckpointUpdated(block.number, _tickPriceAt(2), expectedTotalCleared, expectedCumulativeMps);
        auction.checkpoint();
    }

    function test_submitBid_multipleTicks_succeeds() public {
        uint256 expectedTotalCleared = 100e3 * TOTAL_SUPPLY / AuctionStepLib.MPS;
        uint24 expectedCumulativeMps = 100e3; // 100e3 mps * 1 block

        vm.expectEmit(true, true, true, true);
        // First checkpoint is blank
        emit IAuction.CheckpointUpdated(block.number, _tickPriceAt(1), 0, 0);
        vm.expectEmit(true, true, true, true);
        emit ITickStorage.TickInitialized(_tickPriceAt(2));

        // Bid to purchase 500e18 tokens at a price of 2e6
        auction.submitBid{value: 500e18 * _tickPriceAt(2)}(
            _tickPriceAt(2), true, 500e18 * _tickPriceAt(2), alice, 1, bytes('')
        );

        vm.expectEmit(true, true, true, true);
        emit ITickStorage.TickInitialized(_tickPriceAt(3));
        // Bid 1503 ETH to purchase 501 tokens at a price of 3
        // This bid will move the clearing price because now demand > total supply but no checkpoint is made until the next block
        auction.submitBid{value: 501e18 * _tickPriceAt(3)}(
            _tickPriceAt(3), true, 501e18 * _tickPriceAt(3), alice, 2, bytes('')
        );

        vm.roll(block.number + 1);
        // New block, expect the clearing price to be updated and one block's worth of mps to be sold
        vm.expectEmit(true, true, true, true);
        emit IAuction.CheckpointUpdated(block.number, _tickPriceAt(2), expectedTotalCleared, expectedCumulativeMps);
        auction.checkpoint();
    }

    function test_submitBid_exactIn_atFloorPrice_reverts() public {
        vm.expectRevert(ITickStorage.TickPriceNotIncreasing.selector);
        auction.submitBid{value: 10e18}(_tickPriceAt(1), true, 10e18, alice, 1, bytes(''));
    }

    function test_submitBid_exactOut_atFloorPrice_reverts() public {
        vm.expectRevert(ITickStorage.TickPriceNotIncreasing.selector);
        auction.submitBid{value: 10e18 * _tickPriceAt(1)}(_tickPriceAt(1), false, 10e18, alice, 1, bytes(''));
    }

    function test_submitBid_exactInMsgValue_revertsWithInvalidAmount() public {
        vm.expectRevert(IAuction.InvalidAmount.selector);
        // msg.value should be 1000e18
        auction.submitBid{value: 2000e18}(_tickPriceAt(2), true, 1000e18, alice, 1, bytes(''));
    }

    function test_submitBid_exactInZeroMsgValue_revertsWithInvalidAmount() public {
        vm.expectRevert(IAuction.InvalidAmount.selector);
        auction.submitBid{value: 0}(_tickPriceAt(2), true, 1000e18, alice, 1, bytes(''));
    }

    function test_submitBid_exactOutMsgValue_revertsWithInvalidAmount() public {
        vm.expectRevert(IAuction.InvalidAmount.selector);
        // msg.value should be 2 * 1000e18
        auction.submitBid{value: 1000e18}(_tickPriceAt(2), false, 1000e18, alice, 1, bytes(''));
    }

    function test_submitBid_exactInZeroAmount_revertsWithInvalidAmount() public {
        vm.expectRevert(IAuction.InvalidAmount.selector);
        auction.submitBid{value: 1000e18}(_tickPriceAt(2), true, 0, alice, 1, bytes(''));
    }

    function test_submitBid_exactOutZeroAmount_revertsWithInvalidAmount() public {
        vm.expectRevert(IAuction.InvalidAmount.selector);
        auction.submitBid{value: 1000e18}(_tickPriceAt(2), false, 0, alice, 1, bytes(''));
    }

    function test_submitBid_endBlock_reverts() public {
        vm.roll(auction.endBlock());
        vm.expectRevert(IAuctionStepStorage.AuctionIsOver.selector);
        auction.submitBid{value: 1000e18}(_tickPriceAt(2), true, 1000e18, alice, 1, bytes(''));
    }

    /// forge-config: default.isolate = true
    /// forge-config: ci.isolate = true
    function test_exitBid_succeeds_gas() public {
        uint256 smallAmount = 500e18;
        vm.expectEmit(true, true, true, true);
        emit IAuction.BidSubmitted(0, alice, _tickPriceAt(2), true, smallAmount * _tickPriceAt(2));
        uint256 bidId1 = auction.submitBid{value: smallAmount * _tickPriceAt(2)}(
            _tickPriceAt(2), true, smallAmount * _tickPriceAt(2), alice, 1, bytes('')
        );

        // Bid enough tokens to move the clearing price to 3
        uint256 largeAmount = 1000e18;
        vm.expectEmit(true, true, true, true);
        emit IAuction.BidSubmitted(1, alice, _tickPriceAt(3), true, largeAmount * _tickPriceAt(3));
        uint256 bidId2 = auction.submitBid{value: largeAmount * _tickPriceAt(3)}(
            _tickPriceAt(3), true, largeAmount * _tickPriceAt(3), alice, 2, bytes('')
        );
        uint256 expectedTotalCleared = TOTAL_SUPPLY * 100e3 / AuctionStepLib.MPS;

        vm.roll(block.number + 1);
        vm.expectEmit(true, true, true, true);
        emit IAuction.CheckpointUpdated(block.number, _tickPriceAt(3), expectedTotalCleared, 100e3);
        auction.checkpoint();

        uint256 aliceBalanceBefore = address(alice).balance;
        // Expect that the first bid can be exited, since the clearing price is now above its max price
        vm.expectEmit(true, true, true, true);
        emit IAuction.BidExited(0, alice);
        vm.startPrank(alice);
        auction.exitPartiallyFilledBid(bidId1, 2);
        // Expect that alice is refunded the full amount of the first bid
        assertEq(address(alice).balance - aliceBalanceBefore, smallAmount * _tickPriceAt(2));

        // Expect that the second bid cannot be withdrawn, since the clearing price is below its max price
        vm.expectRevert(IAuction.CannotExitBid.selector);
        auction.exitBid(bidId2);
        vm.stopPrank();
    }

    function test_exitBid_exactOut_succeeds() public {
        uint256 amount = 500e18;
        uint128 maxPrice = _tickPriceAt(2);
        uint256 inputAmount = amount * maxPrice;
        uint256 bidId = auction.submitBid{value: inputAmount}(maxPrice, false, amount, alice, 1, bytes(''));

        vm.roll(block.number + 1);
        auction.checkpoint();

        // Expect the bid to be above clearing price
        assertGt(maxPrice, auction.clearingPrice());

        uint256 aliceBalanceBefore = address(alice).balance;
        uint256 aliceTokenBalanceBefore = token.balanceOf(address(alice));

        vm.roll(auction.endBlock());
        auction.exitBid(bidId);
        // Alice initially deposited 500e18 * 2e6 = 1000e24 ETH
        // They only purchased 500e18 tokens at a price of 1e6, so they should be refunded 1000e24 - 500e18 * 1e6 = 500e18 ETH
        assertEq(address(alice).balance, aliceBalanceBefore + inputAmount - 500e18 * _tickPriceAt(1));

        auction.claimTokens(bidId);
        // Expect fully filled for all tokens
        assertEq(token.balanceOf(address(alice)), aliceTokenBalanceBefore + amount);
    }

    function test_exitBid_afterEndBlock_succeeds() public {
        uint128 bidMaxPrice = _tickPriceAt(3);
        uint256 bidId = auction.submitBid{value: 1000e18 * TICK_SPACING}(
            bidMaxPrice, true, 1000e18 * TICK_SPACING, alice, 1, bytes('')
        );

        vm.roll(block.number + 1);
        vm.expectEmit(true, true, true, true);
        emit IAuction.CheckpointUpdated(block.number, _tickPriceAt(1), TOTAL_SUPPLY * 100e3 / AuctionStepLib.MPS, 100e3);
        auction.checkpoint();

        assertGt(bidMaxPrice, auction.clearingPrice());
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
        uint256 bidId = auction.submitBid{value: 1000e18}(_tickPriceAt(2), true, 1000e18, alice, 1, bytes(''));

        uint256 aliceBalanceBefore = address(alice).balance;
        uint256 aliceTokenBalanceBefore = token.balanceOf(address(alice));
        vm.roll(auction.endBlock());
        auction.exitBid(bidId);
        // Expect no refund since the bid was fully exited
        assertEq(address(alice).balance, aliceBalanceBefore);
        auction.claimTokens(bidId);
        assertEq(token.balanceOf(address(alice)), aliceTokenBalanceBefore + 1000e18 / TICK_SPACING);
    }

    function test_exitBid_beforeEndBlock_revertsWithCannotExitBid() public {
        uint256 bidId = auction.submitBid{value: 1000e18}(_tickPriceAt(3), true, 1000e18, alice, 1, bytes(''));
        // Expect revert because the bid is not below the clearing price
        vm.expectRevert(IAuction.CannotExitBid.selector);
        vm.prank(alice);
        auction.exitBid(bidId);
    }

    function test_exitBid_alreadyExited_revertsWithBidAlreadyExited() public {
        uint256 bidId = auction.submitBid{value: 1000e18}(_tickPriceAt(3), true, 1000e18, alice, 1, bytes(''));
        vm.roll(auction.endBlock());

        vm.startPrank(alice);
        auction.exitBid(bidId);
        vm.expectRevert(IAuction.BidAlreadyExited.selector);
        auction.exitBid(bidId);
        vm.stopPrank();
    }

    function test_exitBid_maxPriceAtClearingPrice_revertsWithCannotExitBid() public {
        uint256 bidId = auction.submitBid{value: 1000e18 * _tickPriceAt(2)}(
            _tickPriceAt(2), true, 1000e18 * _tickPriceAt(2), alice, 1, bytes('')
        );
        vm.roll(block.number + 1);
        auction.checkpoint();
        assertEq(auction.clearingPrice(), _tickPriceAt(2));

        // Auction has ended, but the bid is not exitable through this function because the max price is at the clearing price
        vm.roll(auction.endBlock());
        vm.expectRevert(IAuction.CannotExitBid.selector);
        vm.prank(alice);
        auction.exitBid(bidId);
    }

    /// Simple test for a bid that partially fills at the clearing price but is the only bid at that price, functionally fully filled
    function test_exitPartiallyFilledBid_noOtherBidsAtClearingPrice_succeeds() public {
        uint256 bidId = auction.submitBid{value: 1000e18 * _tickPriceAt(2)}(
            _tickPriceAt(2), true, 1000e18 * _tickPriceAt(2), alice, 1, bytes('')
        );
        vm.roll(block.number + 1);
        auction.checkpoint();

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
        uint256 bidId = auction.submitBid{value: 500e18 * _tickPriceAt(2)}(
            _tickPriceAt(2), true, 500e18 * _tickPriceAt(2), alice, 1, bytes('')
        );
        uint256 bidId2 = auction.submitBid{value: 500e18 * _tickPriceAt(3)}(
            _tickPriceAt(3), true, 500e18 * _tickPriceAt(3), bob, 2, bytes('')
        );

        // Clearing price is at 2
        vm.roll(block.number + 1);
        auction.checkpoint();

        uint256 aliceBalanceBefore = address(alice).balance;
        uint256 bobBalanceBefore = address(bob).balance;
        uint256 aliceTokenBalanceBefore = token.balanceOf(address(alice));
        uint256 bobTokenBalanceBefore = token.balanceOf(address(bob));

        vm.roll(auction.endBlock());
        vm.startPrank(alice);
        auction.exitPartiallyFilledBid(bidId, 2);
        vm.snapshotGasLastCall('exitPartiallyFilledBid');
        // At a clearing price of 2e6,
        // Alice is purchasing 1000e18 / 2 = 500e18 tokens
        // Bob is purchasing 1500e18 / 2 = 750e18 tokens
        // Since the supply is only 1000e18, that means that bob should fully fill for 750e18 tokens, and
        // Alice should partially fill for 250e18 tokens, spending 500e18 ETH
        // Meaning she should be refunded 500e18 ETH
        assertEq(address(alice).balance, aliceBalanceBefore + 250e18 * _tickPriceAt(2));
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
        uint256 bidId1 = auction.submitBid{value: 400e18 * _tickPriceAt(2)}(
            _tickPriceAt(2), true, 400e18 * _tickPriceAt(2), alice, 1, bytes('')
        );
        uint256 bidId2 = auction.submitBid{value: 600e18 * _tickPriceAt(2)}(
            _tickPriceAt(2), true, 600e18 * _tickPriceAt(2), bob, 1, bytes('')
        );

        // Not enough to move the price to 3, but to cause partial fills at 2
        uint256 bidId3 = auction.submitBid{value: 400e18 * _tickPriceAt(3)}(
            _tickPriceAt(3), true, 400e18 * _tickPriceAt(3), charlie, 2, bytes('')
        );

        vm.roll(block.number + 1);
        auction.checkpoint();
        assertEq(auction.clearingPrice(), _tickPriceAt(2));

        uint256 aliceBalanceBefore = address(alice).balance;
        uint256 bobBalanceBefore = address(bob).balance;
        uint256 charlieBalanceBefore = address(charlie).balance;
        uint256 aliceTokenBalanceBefore = token.balanceOf(address(alice));
        uint256 bobTokenBalanceBefore = token.balanceOf(address(bob));
        uint256 charlieTokenBalanceBefore = token.balanceOf(address(charlie));

        // Clearing price is at 2
        // Alice is purchasing 800e24 / 2e6 = 400e18 tokens
        // Bob is purchasing 1200e24 / 2e6 = 600e18 tokens
        // Charlie is purchasing 1500e24 / 3e6 = 500e18 tokens
        // Since the supply is only 1000e18, that means that charlie should fully fill for 600e18 tokens
        // So 400e18 tokens left over
        // Alice should partially fill for 400/1000 * 400e18 = 160e18 tokens
        // - And spent 160e18 * 2 = 320 ETH. She should be refunded 800e18 - 320e18 = 480e18 ETH
        // Bob should partially fill for 600/1000 * 400e18 = 240e18 tokens
        // - And spent 240e18 * 2 = 480 ETH. He should be refunded 1200e18 - 480e18 = 720e18 ETH
        vm.roll(auction.endBlock());

        vm.startPrank(charlie);
        auction.exitBid(bidId3);
        assertEq(address(charlie).balance, charlieBalanceBefore + 0);
        auction.claimTokens(bidId3);
        assertEq(token.balanceOf(address(charlie)), charlieTokenBalanceBefore + 600e18);
        vm.stopPrank();

        vm.startPrank(alice);
        auction.exitPartiallyFilledBid(bidId1, 2);
        assertEq(address(alice).balance, aliceBalanceBefore + 480e18 * TICK_SPACING);
        auction.claimTokens(bidId1);
        assertEq(token.balanceOf(address(alice)), aliceTokenBalanceBefore + 160e18);

        vm.startPrank(bob);
        auction.exitPartiallyFilledBid(bidId2, 2);
        assertEq(address(bob).balance, bobBalanceBefore + 720e18 * TICK_SPACING);
        auction.claimTokens(bidId2);
        assertEq(token.balanceOf(address(bob)), bobTokenBalanceBefore + 240e18);
        vm.stopPrank();
    }
}
