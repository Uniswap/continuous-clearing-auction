// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Auction, AuctionParameters} from '../src/Auction.sol';
import {IAuction} from '../src/interfaces/IAuction.sol';
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
    uint256 public constant TICK_SPACING = 1e18;
    uint128 public constant FLOOR_PRICE = 1e18;
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
        emit ITickStorage.TickInitialized(1, _tickPriceAt(1));
        auction = new Auction(address(token), TOTAL_SUPPLY, params);
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
        emit IAuction.BidSubmitted(0, alice, _tickPriceAt(2), true, TOTAL_SUPPLY * 2);
        auction.submitBid{value: TOTAL_SUPPLY * 2}(_tickPriceAt(2), true, TOTAL_SUPPLY * 2, alice, 1, bytes(''));
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
        auction.submitBid{value: 1000e18 * 2}(_tickPriceAt(2), false, 1000e18, alice, 1, bytes(''));

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
        auction.submitBid{value: 2000e18}(_tickPriceAt(2), true, 2000e18, alice, 1, bytes(''));

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
        emit ITickStorage.TickInitialized(2, _tickPriceAt(2));

        // Bid 1000 ETH to purchase 500 tokens at a price of 2
        auction.submitBid{value: 1000e18}(_tickPriceAt(2), true, 1000e18, alice, 1, bytes(''));

        vm.expectEmit(true, true, true, true);
        emit ITickStorage.TickInitialized(3, _tickPriceAt(3));
        // Bid 1503 ETH to purchase 501 tokens at a price of 3
        // This bid will move the clearing price because now demand > total supply but no checkpoint is made until the next block
        auction.submitBid{value: 1503e18}(_tickPriceAt(3), true, 1503e18, alice, 2, bytes(''));

        vm.roll(block.number + 1);
        // New block, expect the clearing price to be updated and one block's worth of mps to be sold
        vm.expectEmit(true, true, true, true);
        emit IAuction.CheckpointUpdated(block.number, _tickPriceAt(2), expectedTotalCleared, expectedCumulativeMps);
        auction.checkpoint();
    }

    function test_submitBid_exactIn_atFloorPrice_reverts() public {
        vm.expectRevert(BidLib.InvalidBidPrice.selector);
        auction.submitBid{value: 10e18}(_tickPriceAt(1), true, 10e18, alice, 0, bytes(''));
    }

    function test_submitBid_exactOut_atFloorPrice_reverts() public {
        vm.expectRevert(BidLib.InvalidBidPrice.selector);
        auction.submitBid{value: 10e18}(_tickPriceAt(1), false, 10e18, alice, 0, bytes(''));
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

    /// forge-config: default.isolate = true
    function test_withdrawBid_succeeds_gas() public {
        uint256 smallAmount = 500e18;
        vm.expectEmit(true, true, true, true);
        emit IAuction.BidSubmitted(0, alice, _tickPriceAt(2), true, smallAmount);
        uint256 bidId1 = auction.submitBid{value: smallAmount}(_tickPriceAt(2), true, smallAmount, alice, 1, bytes(''));

        // Bid enough to move the clearing price to 3
        uint256 largeAmount = 3000e18;
        vm.expectEmit(true, true, true, true);
        emit IAuction.BidSubmitted(1, alice, _tickPriceAt(3), true, largeAmount);
        uint256 bidId2 = auction.submitBid{value: largeAmount}(_tickPriceAt(3), true, largeAmount, alice, 2, bytes(''));
        uint256 expectedTotalCleared = TOTAL_SUPPLY * 100e3 / AuctionStepLib.MPS;

        vm.roll(block.number + 1);
        vm.expectEmit(true, true, true, true);
        emit IAuction.CheckpointUpdated(block.number, _tickPriceAt(3), expectedTotalCleared, 100e3);
        auction.checkpoint();

        uint256 aliceBalanceBefore = address(alice).balance;
        // Expect that the first bid can be withdrawn, since the clearing price is now above its max price
        vm.expectEmit(true, true, true, true);
        emit IAuction.BidWithdrawn(0, alice);
        vm.prank(alice);
        auction.withdrawPartiallyFilledBid(bidId1, 2);
        vm.snapshotGasLastCall('withdrawBid');
        // Expect that alice is refunded the full amount of the first bid
        uint256 aliceBalanceAfter = address(alice).balance;
        assertEq(aliceBalanceAfter - aliceBalanceBefore, smallAmount);

        // Expect that the second bid cannot be withdrawn, since the clearing price is below its max price
        vm.expectRevert(IAuction.CannotWithdrawBid.selector);
        vm.prank(alice);
        auction.withdrawBid(bidId2);
    }

    function test_withdrawBid_aboveClearingAfterEndBlock_succeeds() public {
        uint128 bidMaxPrice = _tickPriceAt(3);
        uint256 bidId = auction.submitBid{value: 1000e18}(bidMaxPrice, true, 1000e18, alice, 1, bytes(''));

        vm.roll(block.number + 1);
        vm.expectEmit(true, true, true, true);
        emit IAuction.CheckpointUpdated(block.number, _tickPriceAt(1), TOTAL_SUPPLY * 100e3 / AuctionStepLib.MPS, 100e3);
        auction.checkpoint();

        assertGt(bidMaxPrice, auction.clearingPrice());
        // Before the auction ends, the bid should not be withdrawable since it is above the clearing price
        vm.roll(auction.endBlock());
        vm.expectRevert(IAuction.CannotWithdrawBid.selector);
        vm.prank(alice);
        auction.withdrawBid(bidId);

        // Now that the auction has ended, the bid should be withdrawable
        vm.roll(auction.endBlock() + 1);
        vm.prank(alice);
        auction.withdrawBid(bidId);
    }

    function test_withdrawBid_aboveClearingBeforeEndBlock_revertsWithCannotWithdrawBid() public {
        uint256 bidId = auction.submitBid{value: 1000e18}(_tickPriceAt(3), true, 1000e18, alice, 1, bytes(''));
        // Expect revert because the bid is not below the clearing price
        vm.expectRevert(IAuction.CannotWithdrawBid.selector);
        vm.prank(alice);
        auction.withdrawBid(bidId);
    }

    function test_withdrawBid_alreadyWithdrawn_revertsWithBidAlreadyWithdrawn() public {
        uint256 bidId = auction.submitBid{value: 1000e18}(_tickPriceAt(3), true, 1000e18, alice, 1, bytes(''));
        vm.roll(auction.endBlock() + 1);

        vm.startPrank(alice);
        auction.withdrawBid(bidId);
        vm.expectRevert(IAuction.BidAlreadyWithdrawn.selector);
        auction.withdrawBid(bidId);
        vm.stopPrank();
    }

    function test_withdrawBid_maxPriceAtClearingPrice_revertsWithCannotWithdrawBid() public {
        uint256 bidId = auction.submitBid{value: 2000e18}(_tickPriceAt(2), true, 2000e18, alice, 1, bytes(''));
        vm.roll(block.number + 1);
        auction.checkpoint();
        assertEq(auction.clearingPrice(), _tickPriceAt(2));

        // Auction has ended, but the bid is not withdrawable through this function because the max price is at the clearing price
        vm.roll(auction.endBlock() + 1);
        vm.expectRevert(IAuction.CannotWithdrawBid.selector);
        vm.prank(alice);
        auction.withdrawBid(bidId);
    }

    function test_withdrawPartiallyFilledBid_atClearingPrice_succeeds() public {
        uint256 bidId = auction.submitBid{value: 2000e18}(_tickPriceAt(2), true, 2000e18, alice, 1, bytes(''));
        vm.roll(block.number + 1);
        auction.checkpoint();

        vm.roll(auction.endBlock());
        vm.expectRevert(IAuction.CannotWithdrawBid.selector);
        vm.prank(alice);
        auction.withdrawPartiallyFilledBid(bidId, 2);

        uint256 aliceBalanceBefore = address(alice).balance;

        vm.roll(auction.endBlock() + 1);
        vm.prank(alice);
        auction.withdrawPartiallyFilledBid(bidId, 2);

        // Expect no refund
        assertEq(address(alice).balance, aliceBalanceBefore);
    }
}
