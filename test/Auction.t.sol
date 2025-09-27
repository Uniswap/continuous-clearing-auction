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
import {Currency, CurrencyLibrary} from '../src/libraries/CurrencyLibrary.sol';
import {FixedPoint96} from '../src/libraries/FixedPoint96.sol';
import {AuctionBaseTest} from './utils/AuctionBaseTest.sol';
import {AuctionParamsBuilder} from './utils/AuctionParamsBuilder.sol';
import {AuctionStepsBuilder} from './utils/AuctionStepsBuilder.sol';
import {MockAuction} from './utils/MockAuction.sol';
import {MockFundsRecipient} from './utils/MockFundsRecipient.sol';
import {MockToken} from './utils/MockToken.sol';
import {MockValidationHook} from './utils/MockValidationHook.sol';
import {TokenHandler} from './utils/TokenHandler.sol';
import {Test} from 'forge-std/Test.sol';
import {FixedPointMathLib} from 'solady/utils/FixedPointMathLib.sol';
import {SafeTransferLib} from 'solady/utils/SafeTransferLib.sol';

contract AuctionTest is AuctionBaseTest {
    using FixedPointMathLib for uint128;
    using AuctionParamsBuilder for AuctionParameters;
    using AuctionStepsBuilder for bytes;

    function setUp() public {
        setUpAuction();
    }

    /// Return the inputAmount required to purchase at least the given number of tokens at the given maxPrice
    function inputAmountForTokens(uint128 tokens, uint256 maxPrice) internal pure returns (uint128) {
        return uint128(tokens.fullMulDivUp(maxPrice, FixedPoint96.Q96));
    }

    function test_submitBid_beforeTokensReceived_reverts() public {
        Auction newAuction = new Auction(address(token), TOTAL_SUPPLY, params);
        token.mint(address(newAuction), TOTAL_SUPPLY);
        vm.expectRevert(IAuction.TokensNotReceived.selector);
        // Submit random bid, will revert
        newAuction.submitBid{value: inputAmountForTokens(100e18, tickNumberToPriceX96(2))}(
            tickNumberToPriceX96(2),
            true,
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
        uint128 expectedTotalCleared = 10e18; // 100e3 mps * total supply (1000e18)
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
        uint128 expectedTotalCleared = 10e18; // 100e3 mps * total supply (1000e18)
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
        uint128 expectedTotalCleared = 10e18; // 100e3 mps * total supply (1000e18)
        vm.expectEmit(true, true, true, true);
        emit IAuction.CheckpointUpdated(
            block.number, tickNumberToPriceX96(2), expectedTotalCleared, expectedCumulativeMps
        );
        auction.checkpoint();
    }

    function test_submitBid_multipleTicks_succeeds() public {
        uint128 expectedTotalCleared = 100e3 * TOTAL_SUPPLY / AuctionStepLib.MPS;
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
        uint128 inputAmount = inputAmountForTokens(2000e18, tickNumberToPriceX96(2));
        uint256 bidId = auction.submitBid{value: inputAmount}(
            tickNumberToPriceX96(2), true, inputAmount, alice, tickNumberToPriceX96(1), bytes('')
        );

        vm.roll(block.number + 1);
        auction.checkpoint();

        vm.roll(auction.endBlock());
        uint256 aliceBalanceBefore = address(alice).balance;
        uint256 aliceTokenBalanceBefore = token.balanceOf(address(alice));

        auction.exitPartiallyFilledBid(bidId, 1, 0);
        assertEq(address(alice).balance, aliceBalanceBefore + inputAmount / 2);

        vm.roll(auction.claimBlock());
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

        auction.exitPartiallyFilledBid(bidId, 1, 0);
        assertEq(
            address(alice).balance, aliceBalanceBefore + inputAmountForTokens(2000e18, tickNumberToPriceX96(2)) / 2
        );

        vm.roll(auction.claimBlock());
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
        emit IAuction.CheckpointUpdated(block.number, tickNumberToPriceX96(1), 0, 0);
        vm.expectEmit(true, true, true, true);
        emit IAuction.BidSubmitted(0, alice, tickNumberToPriceX96(2), true, inputAmount);
        uint256 bidId = auction.submitBid{value: inputAmount}(
            tickNumberToPriceX96(2), true, inputAmount, alice, tickNumberToPriceX96(1), bytes('')
        );

        // Advance to the next block to get the next checkpoint
        vm.roll(block.number + 1);
        vm.expectEmit(true, true, true, true);
        emit IAuction.CheckpointUpdated(block.number, tickNumberToPriceX96(1), 0, 0);
        auction.checkpoint();
        vm.snapshotGasLastCall('checkpoint_zeroSupply');

        // Advance to the end of the first step
        vm.roll(auction.startBlock() + 101);

        uint128 expectedTotalCleared = 100e3 * TOTAL_SUPPLY / AuctionStepLib.MPS;
        // Now the auction should start clearing
        vm.expectEmit(true, true, true, true);
        emit IAuction.CheckpointUpdated(block.number, tickNumberToPriceX96(2), expectedTotalCleared, 100e3);
        auction.checkpoint();

        vm.roll(auction.endBlock());
        uint256 aliceBalanceBefore = address(alice).balance;
        uint256 aliceTokenBalanceBefore = token.balanceOf(address(alice));

        auction.exitPartiallyFilledBid(bidId, 2, 0);
        assertEq(address(alice).balance, aliceBalanceBefore + inputAmount / 2);

        vm.roll(auction.claimBlock());
        auction.claimTokens(bidId);
        assertEq(token.balanceOf(address(alice)), aliceTokenBalanceBefore + 1000e18);
    }

    function test_submitBid_zeroSupply_exitBid_succeeds() public {
        // 0 mps for first 50 blocks, then 200mps for the last 50 blocks
        params = params.withAuctionStepsData(AuctionStepsBuilder.init().addStep(0, 100).addStep(100e3, 100))
            .withEndBlock(block.number + 200).withClaimBlock(block.number + 200);
        auction = new Auction(address(token), TOTAL_SUPPLY, params);
        token.mint(address(auction), TOTAL_SUPPLY);
        auction.onTokensReceived();

        uint128 inputAmount = inputAmountForTokens(1000e18, tickNumberToPriceX96(1));
        vm.expectEmit(true, true, true, true);
        emit IAuction.CheckpointUpdated(block.number, tickNumberToPriceX96(1), 0, 0);
        vm.expectEmit(true, true, true, true);
        emit IAuction.BidSubmitted(
            0, alice, tickNumberToPriceX96(2), true, inputAmountForTokens(1000e18, tickNumberToPriceX96(1))
        );
        uint256 bidId = auction.submitBid{value: inputAmount}(
            tickNumberToPriceX96(2), true, inputAmount, alice, tickNumberToPriceX96(1), bytes('')
        );

        // Advance to the next block to get the next checkpoint
        vm.roll(block.number + 1);
        vm.expectEmit(true, true, true, true);
        emit IAuction.CheckpointUpdated(block.number, tickNumberToPriceX96(1), 0, 0);
        auction.checkpoint();

        // Advance to the end of the first step
        vm.roll(auction.startBlock() + 101);

        uint128 expectedTotalCleared = 100e3 * TOTAL_SUPPLY / AuctionStepLib.MPS;
        // Now the auction should start clearing
        vm.expectEmit(true, true, true, true);
        emit IAuction.CheckpointUpdated(block.number, tickNumberToPriceX96(1), expectedTotalCleared, 100e3);
        auction.checkpoint();

        vm.roll(auction.endBlock());
        uint256 aliceBalanceBefore = address(alice).balance;
        uint256 aliceTokenBalanceBefore = token.balanceOf(address(alice));

        auction.exitBid(bidId);
        assertEq(address(alice).balance, aliceBalanceBefore + 0);

        vm.roll(auction.claimBlock());
        auction.claimTokens(bidId);
        assertEq(token.balanceOf(address(alice)), aliceTokenBalanceBefore + 1000e18);
    }

    function test_submitBid_afterStartBlock_isPartiallyFilled() public {
        // Advance by one such that the auction is already started
        vm.roll(block.number + 1);
        uint128 inputAmount = inputAmountForTokens(500e18, tickNumberToPriceX96(2));
        uint256 bidId = auction.submitBid{value: inputAmount}(
            tickNumberToPriceX96(2), true, inputAmount, alice, tickNumberToPriceX96(1), bytes('')
        );

        vm.roll(block.number + 1);
        uint128 inputAmount2 = inputAmountForTokens(500e18, tickNumberToPriceX96(2));
        uint256 bidId2 = auction.submitBid{value: inputAmount2}(
            tickNumberToPriceX96(2), true, inputAmount2, alice, tickNumberToPriceX96(1), bytes('')
        );

        vm.roll(block.number + 1);
        auction.checkpoint();

        vm.roll(auction.endBlock());
        // Partially exit the first bid
        auction.exitPartiallyFilledBid(bidId, 3, 0);
        auction.exitPartiallyFilledBid(bidId2, 3, 0);

        uint256 aliceTokenBalanceBefore = token.balanceOf(address(alice));
        vm.roll(auction.claimBlock());
        auction.claimTokens(bidId);
        // Assert that bid1 purchased more than 50% of the tokens (since it participated for one more block than bid2)
        assertGt(token.balanceOf(address(alice)), aliceTokenBalanceBefore + 500e18);
        aliceTokenBalanceBefore = token.balanceOf(address(alice));
        auction.claimTokens(bidId2);
        // Assert that bid2 purchased less than 50% of the tokens
        assertLt(token.balanceOf(address(alice)), aliceTokenBalanceBefore + 500e18);
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
        vm.expectRevert(ITickStorage.TickPreviousPriceInvalid.selector);
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
        vm.expectRevert(ITickStorage.TickPreviousPriceInvalid.selector);
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
    function test_exitBid_succeeds() public {
        uint128 smallAmount = 500e18;
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
        uint128 largeAmount = 1000e18;
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
        uint128 expectedTotalCleared = TOTAL_SUPPLY * 100e3 / AuctionStepLib.MPS;

        vm.roll(block.number + 1);
        vm.expectEmit(true, true, true, true);
        emit IAuction.CheckpointUpdated(block.number, tickNumberToPriceX96(3), expectedTotalCleared, 100e3);
        auction.checkpoint();

        uint256 aliceBalanceBefore = address(alice).balance;
        // Expect that the first bid can be exited, since the clearing price is now above its max price
        vm.expectEmit(true, true, false, false);
        emit IAuction.BidExited(0, alice, 0, 0);
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

        uint128 expectedCurrencyRaised = inputAmountForTokens(largeAmount, tickNumberToPriceX96(3));
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

    function test_exitBid_exactOut_succeeds() public {
        uint128 amount = 500e18;
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

        vm.roll(auction.endBlock());
        auction.exitBid(bidId);
        // Alice initially deposited 500e18 * tickNumberToPrice(2e6) = 1000e24 ETH
        // They only purchased 500e18 tokens at a price of 1e6, so they should be refunded 1000e24 - 500e18 * tickNumberToPrice(1e6) = 500e18 ETH
        assertEq(
            address(alice).balance,
            aliceBalanceBefore + inputAmountForTokens(500e18, tickNumberToPriceX96(2))
                - inputAmountForTokens(500e18, tickNumberToPriceX96(1))
        );

        vm.roll(auction.claimBlock());
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
        vm.expectRevert(IAuction.AuctionIsNotOver.selector);
        auction.exitBid(bidId);

        uint256 aliceBalanceBefore = address(alice).balance;

        // Now that the auction has ended, the bid should be exitable
        vm.roll(auction.endBlock());
        auction.exitBid(bidId);
        // Expect no refund
        assertEq(address(alice).balance, aliceBalanceBefore);
        vm.roll(auction.claimBlock());
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
        vm.roll(auction.claimBlock());
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
        vm.roll(auction.endBlock());
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

        // Roll to end of auction
        vm.roll(auction.endBlock());
        uint128 expectedCurrencyRaised = inputAmountForTokens(750e18, tickNumberToPriceX96(11))
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
            true,
            inputAmountForTokens(400e18, tickNumberToPriceX96(5)),
            alice,
            tickNumberToPriceX96(1),
            bytes('')
        );

        vm.roll(block.number + 1);
        uint256 bidId2 = auction.submitBid{value: inputAmountForTokens(600e18, tickNumberToPriceX96(5))}(
            tickNumberToPriceX96(5),
            true,
            inputAmountForTokens(600e18, tickNumberToPriceX96(5)),
            bob,
            tickNumberToPriceX96(1),
            bytes('')
        );

        vm.roll(block.number + 1);
        // Not enough to move the price to 3, but to cause partial fills at 2
        uint256 bidId3 = auction.submitBid{value: inputAmountForTokens(500e18, tickNumberToPriceX96(6))}(
            tickNumberToPriceX96(6),
            true,
            inputAmountForTokens(500e18, tickNumberToPriceX96(6)),
            charlie,
            tickNumberToPriceX96(5),
            bytes('')
        );

        vm.roll(block.number + 1);
        uint256 bidId4 = auction.submitBid{value: inputAmountForTokens(1, tickNumberToPriceX96(6))}(
            tickNumberToPriceX96(6), false, 1, charlie, tickNumberToPriceX96(5), bytes('')
        );

        vm.roll(block.number + 1);
        auction.checkpoint();
        assertEq(auction.clearingPrice(), tickNumberToPriceX96(5));

        // Roll to end of auction
        vm.roll(auction.endBlock());

        vm.startPrank(auction.fundsRecipient());
        auction.sweepCurrency();
        vm.stopPrank();

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
    }

    function test_fuzzReplay_roundingErrors_succeeds() public {
        vm.roll(2);
        vm.roll(3);
        vm.roll(4);
        auction.submitBid{value: 16_951_001}(
            79_228_162_514_264_337_593_543_950_341_500,
            false,
            16_951,
            alice,
            79_228_162_514_264_337_593_543_950_336_000,
            bytes('')
        );

        vm.roll(5);
        auction.checkpoint();

        vm.roll(6);
        auction.submitBid{value: 1_938_195_602_430_274_713_814_001}(
            79_228_162_514_264_337_593_543_950_357_400,
            false,
            1_938_195_602_430_274_713_814,
            alice,
            79_228_162_514_264_337_593_543_950_341_500,
            bytes('')
        );

        vm.roll(101);
        auction.checkpoint();

        auction.exitPartiallyFilledBid(0, 6, 101);
        auction.exitPartiallyFilledBid(1, 6, 101);

        vm.roll(auction.claimBlock());
        auction.claimTokens(0);
        auction.claimTokens(1);
    }

    function test_fuzzReplay_supplyCausingRoundingErrors_succeeds() public {
        vm.roll(2);
        auction.submitBid{value: 305_286_001}(
            79_228_162_514_264_337_593_543_950_349_400,
            false,
            305_286,
            alice,
            79_228_162_514_264_337_593_543_950_336_000,
            bytes('')
        );

        auction.submitBid{value: 233_715_034_573_585_010_487_001}(
            79_228_162_514_264_337_593_543_950_341_500,
            false,
            233_715_034_573_585_010_487,
            alice,
            79_228_162_514_264_337_593_543_950_336_000,
            bytes('')
        );

        auction.submitBid{value: 894_591_511_812_533_175_189_001}(
            79_228_162_514_264_337_593_543_950_350_900,
            false,
            894_591_511_812_533_175_189,
            alice,
            79_228_162_514_264_337_593_543_950_349_400,
            bytes('')
        );

        vm.roll(101);
        auction.checkpoint();

        auction.exitBid(0);
        auction.exitPartiallyFilledBid(1, 2, 0);
        auction.exitBid(2);

        vm.roll(auction.claimBlock());
        auction.claimTokens(0);
        auction.claimTokens(1);
        auction.claimTokens(2);
    }

    function test_onTokensReceived_withCorrectTokenAndAmount_succeeds() public {
        vm.expectEmit(true, true, true, true);
        emit IAuction.TokensReceived(TOTAL_SUPPLY);
        auction.onTokensReceived();
    }

    function test_onTokensReceived_withWrongBalance_reverts() public {
        // Use salt to get a new address
        Auction newAuction = new Auction{salt: bytes32(uint256(1))}(address(token), TOTAL_SUPPLY, params);

        token.mint(address(newAuction), TOTAL_SUPPLY - 1);

        vm.expectRevert(IAuction.IDistributionContract__InvalidAmountReceived.selector);
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
    function test_calculateNewClearingPrice_withNoDemand() public {
        // Don't submit any bids
        vm.roll(block.number + 1);
        auction.checkpoint();
        vm.snapshotGasLastCall('checkpoint_noBids');

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
        auction.exitPartiallyFilledBid(bidId, 2, 2);
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
        uint256 bidId = mockAuction.createBid(true, 100e18, alice, tickNumberToPriceX96(2));
        Bid memory bid = mockAuction.getBid(bidId);
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
            vm.expectRevert(IAuction.InvalidCheckpointHint.selector);
            mockAuction.exitPartiallyFilledBid(bidId, i, 5);
        }
    }

    function test_advanceToCurrentStep_withMultipleStepsAndClearingPrice() public {
        auctionStepsData = AuctionStepsBuilder.init().addStep(100e3, 20).addStep(150e3, 20).addStep(250e3, 20);
        params = params.withEndBlock(block.number + 60).withAuctionStepsData(auctionStepsData);

        Auction newAuction = new Auction(address(token), TOTAL_SUPPLY, params);
        token.mint(address(newAuction), TOTAL_SUPPLY);
        newAuction.onTokensReceived();

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

        uint24 mps = newAuction.step().mps;
        assertEq(mps, 150e3);

        vm.roll(block.number + 20);
        newAuction.checkpoint();

        AuctionStep memory step = newAuction.step();
        assertEq(step.mps, 250e3);
    }

    function test_calculateNewClearingPrice_belowFloorPrice_returnsFloorPrice() public {
        params = params.withFloorPrice(10e6 << FixedPoint96.RESOLUTION);

        MockAuction mockAuction = new MockAuction(address(token), TOTAL_SUPPLY, params);
        token.mint(address(mockAuction), TOTAL_SUPPLY);
        mockAuction.onTokensReceived();

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
        uint128 blockTokenSupply = 1e22; // Even larger supply to get a smaller calculated price

        uint256 result = mockAuction.calculateNewClearingPrice(
            minimumClearingPrice, // minimumClearingPrice in X96 (below floor price)
            blockTokenSupply // blockTokenSupply
        );

        assertEq(result, 10e6 << FixedPoint96.RESOLUTION);
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
            true,
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
        params = params.withCurrency(address(currency));
        Auction erc20Auction = new Auction(address(token), TOTAL_SUPPLY, params);
        token.mint(address(erc20Auction), TOTAL_SUPPLY);
        erc20Auction.onTokensReceived();
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

    function test_submitBid_withERC20Currency_nonZeroMsgValue_reverts() public {
        // Create auction parameters with ERC20 currency instead of ETH
        params = params.withCurrency(address(currency));
        Auction erc20Auction = new Auction(address(token), TOTAL_SUPPLY, params);
        token.mint(address(erc20Auction), TOTAL_SUPPLY);
        erc20Auction.onTokensReceived();

        // Mint currency tokens to alice
        currency.mint(alice, 1000e18);

        // For now, let's just verify that the currency is set correctly
        assertEq(Currency.unwrap(erc20Auction.currency()), address(currency));
        assertFalse(erc20Auction.currency().isAddressZero());

        vm.expectRevert(IAuction.CurrencyIsNotNative.selector);
        erc20Auction.submitBid{value: 100e18}(
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
        auction.exitPartiallyFilledBid(bidId, 2, 2);
    }

    function test_auctionConstruction_revertsWithTotalSupplyZero() public {
        vm.expectRevert(ITokenCurrencyStorage.TotalSupplyIsZero.selector);
        new Auction(address(token), 0, params);
    }

    function test_auctionConstruction_revertsWithTickSpacingZero() public {
        AuctionParameters memory paramsZeroTickSpacing = params.withTickSpacing(0);
        vm.expectRevert(ITickStorage.TickSpacingIsZero.selector);
        new Auction(address(token), TOTAL_SUPPLY, paramsZeroTickSpacing);
    }

    function test_auctionConstruction_revertsWithFloorPriceZero() public {
        AuctionParameters memory paramsZeroFloorPrice = params.withFloorPrice(0);
        vm.expectRevert(IAuction.FloorPriceIsZero.selector);
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

    function test_auctionConstruction_revertsWithInvalidGraduationThresholdMps() public {
        AuctionParameters memory paramsInvalidGraduationThresholdMps = params.withGraduationThresholdMps(1e7 + 1);
        vm.expectRevert(ITokenCurrencyStorage.InvalidGraduationThresholdMps.selector);
        new Auction(address(token), TOTAL_SUPPLY, paramsInvalidGraduationThresholdMps);
    }

    function test_checkpoint_beforeAuctionStarts_reverts() public {
        // Create an auction that starts in the future
        uint256 futureBlock = block.number + 10;
        params = params.withStartBlock(futureBlock).withEndBlock(futureBlock + AUCTION_DURATION).withClaimBlock(
            futureBlock + AUCTION_DURATION
        );

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

    function test_submitBid_atEndBlock_reverts() public {
        // Advance to after the auction ends
        vm.roll(auction.endBlock());

        // Try to submit a bid at the end block
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
        auction.exitPartiallyFilledBid(bidId, 1, 0);

        // Try to exit the same bid again - this should revert with BidAlreadyExited on line 294
        vm.expectRevert(IAuction.BidAlreadyExited.selector);
        auction.exitPartiallyFilledBid(bidId, 1, 0);

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
        auction.exitPartiallyFilledBid(bidId, 1, 1);

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
        vm.roll(auction.claimBlock());
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
        vm.roll(auction.endBlock());
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
        Auction failingAuction = new Auction(address(failingToken), TOTAL_SUPPLY, params);
        failingToken.mint(address(failingAuction), TOTAL_SUPPLY);
        failingAuction.onTokensReceived();

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
            true,
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

    function test_sweepCurrency_notGraduated_reverts() public {
        // Create an auction with a high graduation threshold
        params = params.withGraduationThresholdMps(1e7 / 2);

        Auction auctionWithThreshold = new Auction(address(token), TOTAL_SUPPLY, params);
        token.mint(address(auctionWithThreshold), TOTAL_SUPPLY);
        auctionWithThreshold.onTokensReceived();

        // Submit a small bid (only 10% of supply, below 50% threshold)
        uint128 smallAmount = TOTAL_SUPPLY / 10;
        auctionWithThreshold.submitBid{value: inputAmountForTokens(smallAmount, tickNumberToPriceX96(2))}(
            tickNumberToPriceX96(2),
            true,
            inputAmountForTokens(smallAmount, tickNumberToPriceX96(2)),
            alice,
            tickNumberToPriceX96(1),
            bytes('')
        );

        vm.roll(auctionWithThreshold.endBlock());

        vm.prank(fundsRecipient);
        vm.expectRevert(ITokenCurrencyStorage.NotGraduated.selector);
        auctionWithThreshold.sweepCurrency();
    }

    function test_sweepCurrency_graduated_succeeds() public {
        // 30% graduation threshold
        params = params.withGraduationThresholdMps(30e5);

        Auction auctionWithThreshold = new Auction(address(token), TOTAL_SUPPLY, params);
        token.mint(address(auctionWithThreshold), TOTAL_SUPPLY);
        auctionWithThreshold.onTokensReceived();
        // Submit a bid for 50% of supply (above 30% threshold)
        uint128 halfSupply = TOTAL_SUPPLY / 2;
        uint128 inputAmount = inputAmountForTokens(halfSupply, tickNumberToPriceX96(2));
        auctionWithThreshold.submitBid{value: inputAmount}(
            tickNumberToPriceX96(2), true, inputAmount, alice, tickNumberToPriceX96(1), bytes('')
        );

        vm.roll(auctionWithThreshold.endBlock());

        vm.prank(fundsRecipient);
        vm.expectEmit(true, true, true, true);
        emit ITokenCurrencyStorage.CurrencySwept(fundsRecipient, inputAmount);
        auctionWithThreshold.sweepCurrency();

        // Verify funds were transferred
        assertEq(fundsRecipient.balance, inputAmount);
    }

    // fundsRecipientData tests

    function test_sweepCurrency_withFundsRecipientData_callsRecipient() public {
        // Set up auction with MockFundsRecipient and callback data
        bytes memory callbackData = abi.encodeWithSignature('fallback()');
        params = params.withGraduationThresholdMps(30e5).withFundsRecipient(address(mockFundsRecipient))
            .withFundsRecipientData(callbackData);

        Auction auctionWithCallback = new Auction(address(token), TOTAL_SUPPLY, params);
        token.mint(address(auctionWithCallback), TOTAL_SUPPLY);
        auctionWithCallback.onTokensReceived();

        // Submit a bid for 50% of supply (above 30% threshold)
        uint128 halfSupply = TOTAL_SUPPLY / 2;
        uint128 inputAmount = inputAmountForTokens(halfSupply, tickNumberToPriceX96(2));
        auctionWithCallback.submitBid{value: inputAmount}(
            tickNumberToPriceX96(2), true, inputAmount, alice, tickNumberToPriceX96(1), bytes('')
        );

        vm.roll(auctionWithCallback.endBlock());
        // Update the lastCheckpoint to register the auction as graduated
        auctionWithCallback.checkpoint();

        // Expect the callback to be made with the specified data
        vm.expectCall(address(mockFundsRecipient), callbackData);

        // The callback should succeed and emit the event
        vm.prank(address(mockFundsRecipient));
        vm.expectEmit(true, true, true, true);
        emit ITokenCurrencyStorage.CurrencySwept(address(mockFundsRecipient), inputAmount);
        auctionWithCallback.sweepCurrency();

        // Verify funds were transferred
        assertEq(address(mockFundsRecipient).balance, inputAmount);
    }

    function test_sweepCurrency_withFundsRecipientData_revertsWithReason() public {
        // Set up auction with MockFundsRecipient and callback data that will revert
        bytes memory revertReason = bytes('Custom revert reason');
        params = params.withGraduationThresholdMps(30e5).withFundsRecipient(address(mockFundsRecipient))
            .withFundsRecipientData(abi.encodeWithSignature('revertWithReason(bytes)', revertReason));

        Auction auctionWithCallback = new Auction(address(token), TOTAL_SUPPLY, params);
        token.mint(address(auctionWithCallback), TOTAL_SUPPLY);
        auctionWithCallback.onTokensReceived();

        // Submit a bid for 50% of supply (above 30% threshold)
        uint128 halfSupply = TOTAL_SUPPLY / 2;
        uint128 inputAmount = inputAmountForTokens(halfSupply, tickNumberToPriceX96(2));
        auctionWithCallback.submitBid{value: inputAmount}(
            tickNumberToPriceX96(2), true, inputAmount, alice, tickNumberToPriceX96(1), bytes('')
        );

        vm.roll(auctionWithCallback.endBlock());
        // Update the lastCheckpoint to register the auction as graduated
        auctionWithCallback.checkpoint();

        // The callback should revert with the custom reason
        vm.prank(address(mockFundsRecipient));
        vm.expectRevert('Custom revert reason');
        auctionWithCallback.sweepCurrency();
    }

    function test_sweepCurrency_withFundsRecipientData_revertsWithoutReason() public {
        // Set up auction with MockFundsRecipient and callback data that will revert without reason
        params = params.withGraduationThresholdMps(30e5).withFundsRecipient(address(mockFundsRecipient))
            .withFundsRecipientData(abi.encodeWithSignature('revertWithoutReason()'));

        Auction auctionWithCallback = new Auction(address(token), TOTAL_SUPPLY, params);
        token.mint(address(auctionWithCallback), TOTAL_SUPPLY);
        auctionWithCallback.onTokensReceived();

        // Submit a bid for 50% of supply (above 30% threshold)
        uint128 halfSupply = TOTAL_SUPPLY / 2;
        uint128 inputAmount = inputAmountForTokens(halfSupply, tickNumberToPriceX96(2));
        auctionWithCallback.submitBid{value: inputAmount}(
            tickNumberToPriceX96(2), true, inputAmount, alice, tickNumberToPriceX96(1), bytes('')
        );

        vm.roll(auctionWithCallback.endBlock());
        // Update the lastCheckpoint to register the auction as graduated
        auctionWithCallback.checkpoint();

        // The callback should revert without a reason
        vm.prank(address(mockFundsRecipient));
        vm.expectRevert();
        auctionWithCallback.sweepCurrency();
    }

    function test_sweepCurrency_withFundsRecipientData_EOA_doesNotCall() public {
        // Set up auction with EOA recipient and callback data (should not call)
        params = params.withGraduationThresholdMps(30e5).withFundsRecipient(fundsRecipient) // EOA
            .withFundsRecipientData(abi.encodeWithSignature('someFunction()'));

        Auction auctionWithCallback = new Auction(address(token), TOTAL_SUPPLY, params);
        token.mint(address(auctionWithCallback), TOTAL_SUPPLY);
        auctionWithCallback.onTokensReceived();

        // Submit a bid for 50% of supply (above 30% threshold)
        uint128 halfSupply = TOTAL_SUPPLY / 2;
        uint128 inputAmount = inputAmountForTokens(halfSupply, tickNumberToPriceX96(2));
        auctionWithCallback.submitBid{value: inputAmount}(
            tickNumberToPriceX96(2), true, inputAmount, alice, tickNumberToPriceX96(1), bytes('')
        );

        vm.roll(auctionWithCallback.endBlock());
        // Update the lastCheckpoint to register the auction as graduated
        auctionWithCallback.checkpoint();

        // Should succeed without calling the EOA (EOAs have no code)
        vm.prank(fundsRecipient);
        vm.expectEmit(true, true, true, true);
        emit ITokenCurrencyStorage.CurrencySwept(fundsRecipient, inputAmount);
        auctionWithCallback.sweepCurrency();

        // Verify funds were transferred
        assertEq(fundsRecipient.balance, inputAmount);
    }

    function test_sweepCurrency_withoutFundsRecipientData_doesNotCall() public {
        // Set up auction with MockFundsRecipient but no callback data
        params = params.withGraduationThresholdMps(30e5).withFundsRecipient(address(mockFundsRecipient))
            .withFundsRecipientData(bytes('')); // Empty data

        Auction auctionWithCallback = new Auction(address(token), TOTAL_SUPPLY, params);
        token.mint(address(auctionWithCallback), TOTAL_SUPPLY);
        auctionWithCallback.onTokensReceived();

        // Submit a bid for 50% of supply (above 30% threshold)
        uint128 halfSupply = TOTAL_SUPPLY / 2;
        uint128 inputAmount = inputAmountForTokens(halfSupply, tickNumberToPriceX96(2));
        auctionWithCallback.submitBid{value: inputAmount}(
            tickNumberToPriceX96(2), true, inputAmount, alice, tickNumberToPriceX96(1), bytes('')
        );

        vm.roll(auctionWithCallback.endBlock());
        // Update the lastCheckpoint to register the auction as graduated
        auctionWithCallback.checkpoint();

        // Should succeed without calling the contract (no data provided)
        vm.prank(address(mockFundsRecipient));
        vm.expectEmit(true, true, true, true);
        emit ITokenCurrencyStorage.CurrencySwept(address(mockFundsRecipient), inputAmount);
        auctionWithCallback.sweepCurrency();

        // Verify funds were transferred
        assertEq(address(mockFundsRecipient).balance, inputAmount);
    }

    function test_sweepCurrency_withFundsRecipientData_contractRecipientSucceedsWithValidData() public {
        // Create a more complex callback scenario with a contract recipient
        MockFundsRecipient contractRecipient = new MockFundsRecipient();

        // Set up auction with contract recipient and valid callback data
        bytes memory callbackData = abi.encodeWithSignature('fallback()');
        params = params.withGraduationThresholdMps(30e5).withFundsRecipient(address(contractRecipient))
            .withFundsRecipientData(callbackData);

        Auction auctionWithCallback = new Auction(address(token), TOTAL_SUPPLY, params);
        token.mint(address(auctionWithCallback), TOTAL_SUPPLY);
        auctionWithCallback.onTokensReceived();

        // Submit a bid for 50% of supply (above 30% threshold)
        uint128 halfSupply = TOTAL_SUPPLY / 2;
        uint128 inputAmount = inputAmountForTokens(halfSupply, tickNumberToPriceX96(2));
        auctionWithCallback.submitBid{value: inputAmount}(
            tickNumberToPriceX96(2), true, inputAmount, alice, tickNumberToPriceX96(1), bytes('')
        );

        vm.roll(auctionWithCallback.endBlock());
        // Update the lastCheckpoint to register the auction as graduated
        auctionWithCallback.checkpoint();

        // Verify the contract receives funds and the callback is executed
        uint256 balanceBefore = address(contractRecipient).balance;

        // Expect the callback to be made with the specified data
        vm.expectCall(address(contractRecipient), callbackData);

        vm.prank(address(contractRecipient));
        vm.expectEmit(true, true, true, true);
        emit ITokenCurrencyStorage.CurrencySwept(address(contractRecipient), inputAmount);
        auctionWithCallback.sweepCurrency();

        // Verify funds were transferred
        assertEq(address(contractRecipient).balance, balanceBefore + inputAmount);
    }

    function test_sweepCurrency_withFundsRecipientData_multipleCallsWithDifferentData() public {
        // Test that the data is correctly stored and used
        bytes memory firstCallData = abi.encodeWithSignature('fallback()');
        params = params.withGraduationThresholdMps(30e5).withFundsRecipient(address(mockFundsRecipient))
            .withFundsRecipientData(firstCallData);

        Auction firstAuction = new Auction(address(token), TOTAL_SUPPLY, params);
        token.mint(address(firstAuction), TOTAL_SUPPLY);
        firstAuction.onTokensReceived();

        // Second auction with different callback data
        bytes memory secondCallData = abi.encodeWithSignature('revertWithReason(bytes)', bytes('Should revert'));
        AuctionParameters memory params2 = params.withFundsRecipientData(secondCallData);

        Auction secondAuction = new Auction{salt: bytes32(uint256(2))}(address(token), TOTAL_SUPPLY, params2);
        token.mint(address(secondAuction), TOTAL_SUPPLY);
        secondAuction.onTokensReceived();

        // Submit bids to both auctions
        uint128 halfSupply = TOTAL_SUPPLY / 2;
        uint128 inputAmount = inputAmountForTokens(halfSupply, tickNumberToPriceX96(2));

        firstAuction.submitBid{value: inputAmount}(
            tickNumberToPriceX96(2), true, inputAmount, alice, tickNumberToPriceX96(1), bytes('')
        );

        secondAuction.submitBid{value: inputAmount}(
            tickNumberToPriceX96(2), true, inputAmount, alice, tickNumberToPriceX96(1), bytes('')
        );

        vm.roll(firstAuction.endBlock());
        // Update the lastCheckpoint to register the auction as graduated
        firstAuction.checkpoint();

        vm.roll(secondAuction.endBlock());
        // Update the lastCheckpoint to register the auction as graduated
        secondAuction.checkpoint();

        // First auction should succeed - expect the callback to be made
        vm.expectCall(address(mockFundsRecipient), firstCallData);
        vm.prank(address(mockFundsRecipient));
        firstAuction.sweepCurrency();

        // Second auction should revert with the expected message
        vm.prank(address(mockFundsRecipient));
        vm.expectRevert('Should revert');
        secondAuction.sweepCurrency();
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

    function test_sweepUnsoldTokens_graduated_sweepsUnsold() public {
        // 30% graduation threshold
        params = params.withGraduationThresholdMps(30e5);

        Auction auctionWithThreshold = new Auction(address(token), TOTAL_SUPPLY, params);
        token.mint(address(auctionWithThreshold), TOTAL_SUPPLY);
        auctionWithThreshold.onTokensReceived();
        // Submit a bid for 60% of supply (above 30% threshold, so graduated)
        uint128 soldAmount = (TOTAL_SUPPLY * 60) / 100;
        uint128 inputAmount = inputAmountForTokens(soldAmount, tickNumberToPriceX96(1));
        auctionWithThreshold.submitBid{value: inputAmount}(
            tickNumberToPriceX96(2), true, inputAmount, alice, tickNumberToPriceX96(1), bytes('')
        );

        vm.roll(auctionWithThreshold.endBlock());

        // Should sweep only unsold tokens (40% of supply)
        uint128 expectedUnsoldTokens = TOTAL_SUPPLY - soldAmount;

        vm.expectEmit(true, true, true, true);
        emit ITokenCurrencyStorage.TokensSwept(tokensRecipient, expectedUnsoldTokens);
        auctionWithThreshold.sweepUnsoldTokens();

        // Verify tokens were transferred
        assertEq(token.balanceOf(tokensRecipient), expectedUnsoldTokens);
    }

    function test_sweepUnsoldTokens_notGraduated_sweepsAll() public {
        // Create an auction with high graduation threshold (50%)
        params = params.withGraduationThresholdMps(1e7 / 2);
        Auction auctionWithThreshold = new Auction(address(token), TOTAL_SUPPLY, params);
        token.mint(address(auctionWithThreshold), TOTAL_SUPPLY);
        auctionWithThreshold.onTokensReceived();
        // Submit a small bid for 10% of supply (below 50% threshold, so not graduated)
        uint128 smallAmount = TOTAL_SUPPLY / 10;
        uint128 inputAmount = inputAmountForTokens(smallAmount, tickNumberToPriceX96(1));
        auctionWithThreshold.submitBid{value: inputAmount}(
            tickNumberToPriceX96(2), true, inputAmount, alice, tickNumberToPriceX96(1), bytes('')
        );

        vm.roll(auctionWithThreshold.endBlock());
        // Update the lastCheckpoint
        auctionWithThreshold.checkpoint();

        // Should sweep ALL tokens since auction didn't graduate
        vm.expectEmit(true, true, true, true);
        emit ITokenCurrencyStorage.TokensSwept(tokensRecipient, TOTAL_SUPPLY);
        auctionWithThreshold.sweepUnsoldTokens();

        // Verify all tokens were transferred
        assertEq(token.balanceOf(tokensRecipient), TOTAL_SUPPLY);
    }

    function test_sweepCurrency_thenSweepTokens_graduated_succeeds() public {
        // Create an auction with graduation threshold (40%)
        params = params.withGraduationThresholdMps(40e5);

        Auction auctionWithThreshold = new Auction(address(token), TOTAL_SUPPLY, params);
        token.mint(address(auctionWithThreshold), TOTAL_SUPPLY);
        auctionWithThreshold.onTokensReceived();
        // Submit a bid for 70% of supply (above threshold)
        uint128 soldAmount = (TOTAL_SUPPLY * 70) / 100;
        uint128 inputAmount = inputAmountForTokens(soldAmount, tickNumberToPriceX96(1));
        auctionWithThreshold.submitBid{value: inputAmount}(
            tickNumberToPriceX96(2), true, inputAmount, alice, tickNumberToPriceX96(1), bytes('')
        );

        vm.roll(auctionWithThreshold.endBlock());

        // Sweep currency first (should succeed as graduated)
        uint128 expectedCurrencyRaised = inputAmountForTokens(soldAmount, tickNumberToPriceX96(1));
        vm.prank(fundsRecipient);
        vm.expectEmit(true, true, true, true);
        emit ITokenCurrencyStorage.CurrencySwept(fundsRecipient, expectedCurrencyRaised);
        auctionWithThreshold.sweepCurrency();

        // Then sweep unsold tokens
        uint128 expectedUnsoldTokens = TOTAL_SUPPLY - soldAmount;
        vm.expectEmit(true, true, true, true);
        emit ITokenCurrencyStorage.TokensSwept(tokensRecipient, expectedUnsoldTokens);
        auctionWithThreshold.sweepUnsoldTokens();

        // Verify transfers
        assertEq(fundsRecipient.balance, expectedCurrencyRaised);
        assertEq(token.balanceOf(tokensRecipient), expectedUnsoldTokens);
    }

    function test_sweepTokens_notGraduated_cannotSweepCurrency() public {
        // Create an auction with high graduation threshold (80%)
        params = params.withGraduationThresholdMps(80e5);

        Auction auctionWithThreshold = new Auction(address(token), TOTAL_SUPPLY, params);
        token.mint(address(auctionWithThreshold), TOTAL_SUPPLY);
        auctionWithThreshold.onTokensReceived();
        // Submit a bid for only 20% of supply (below 80% threshold)
        uint128 smallAmount = TOTAL_SUPPLY / 5;
        uint128 inputAmount = inputAmountForTokens(smallAmount, tickNumberToPriceX96(1));
        auctionWithThreshold.submitBid{value: inputAmount}(
            tickNumberToPriceX96(2), true, inputAmount, alice, tickNumberToPriceX96(1), bytes('')
        );

        vm.roll(auctionWithThreshold.endBlock());
        // Update the lastCheckpoint
        auctionWithThreshold.checkpoint();

        // Can sweep tokens (returns all since not graduated)
        vm.expectEmit(true, true, true, true);
        emit ITokenCurrencyStorage.TokensSwept(tokensRecipient, TOTAL_SUPPLY);
        auctionWithThreshold.sweepUnsoldTokens();

        // Cannot sweep currency (not graduated)
        vm.prank(fundsRecipient);
        vm.expectRevert(ITokenCurrencyStorage.NotGraduated.selector);
        auctionWithThreshold.sweepCurrency();
    }
}
