// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Auction} from '../src/Auction.sol';
import {AuctionParameters, IAuction} from '../src/interfaces/IAuction.sol';
import {BidLib} from '../src/libraries/BidLib.sol';
import {Checkpoint} from '../src/libraries/CheckpointLib.sol';
import {ConstantsLib} from '../src/libraries/ConstantsLib.sol';
import {FixedPoint96} from '../src/libraries/FixedPoint96.sol';
import {ValueX7, ValueX7Lib} from '../src/libraries/ValueX7Lib.sol';
import {Assertions} from './utils/Assertions.sol';
import {AuctionBaseTest} from './utils/AuctionBaseTest.sol';
import {AuctionParamsBuilder} from './utils/AuctionParamsBuilder.sol';
import {AuctionStepsBuilder} from './utils/AuctionStepsBuilder.sol';
import {Test} from 'forge-std/Test.sol';
import {FixedPointMathLib} from 'solady/utils/FixedPointMathLib.sol';

/// @title AuctionStepDiffTest
/// @notice Tests for different auction steps data combinations
contract AuctionStepDiffTest is AuctionBaseTest {
    using FixedPointMathLib for *;
    using AuctionParamsBuilder for AuctionParameters;
    using AuctionStepsBuilder for bytes;

    function setUp() public {
        setUpTokens();
        alice = makeAddr('alice');
        tokensRecipient = makeAddr('tokensRecipient');
        fundsRecipient = makeAddr('fundsRecipient');

        // Missing start block, end block, claim block, and auction steps data
        params = AuctionParamsBuilder.init().withCurrency(ETH_SENTINEL).withFloorPrice(FLOOR_PRICE)
            .withTickSpacing(TICK_SPACING).withValidationHook(address(0)).withTokensRecipient(tokensRecipient)
            .withFundsRecipient(fundsRecipient);
    }

    function fuzzAuctionStepsData(uint8 steps) public pure returns (bytes memory, uint24, uint40) {
        vm.assume(steps > 0);
        bytes memory data = AuctionStepsBuilder.init();
        uint24 cumulativeMps = 0;
        uint40 cumulativeBlockDelta = 0;
        // Assumes block delta is 1 for simplicity
        for (uint8 i = 0; i < steps && cumulativeMps < ConstantsLib.MPS; i++) {
            uint24 fuzzMps;
            uint24 remainingSupply = ConstantsLib.MPS - cumulativeMps;
            // Bias towards 0
            if (i % 2 == 0) {
                fuzzMps = 0;
            } else {
                fuzzMps = uint24(bound(uint256(keccak256(abi.encode(i, steps))), 0, remainingSupply));
            }
            // If the total mps is greater than the max mps, set the mps to the max mps and the block delta to 1
            if (fuzzMps > remainingSupply) {
                fuzzMps = remainingSupply;
            }
            cumulativeMps += fuzzMps;
            cumulativeBlockDelta++;
            data = data.addStep(fuzzMps, 1);
        }
        if (cumulativeMps < ConstantsLib.MPS) {
            uint24 remainingSupply = ConstantsLib.MPS - cumulativeMps;

            data = data.addStep(uint24(remainingSupply), 1);
            cumulativeMps += remainingSupply;
            cumulativeBlockDelta++;
        }
        assertEq(cumulativeMps, ConstantsLib.MPS, 'fuzzed cumulative mps is not equal to the max mps');
        return (data, cumulativeMps, cumulativeBlockDelta);
    }

    function test_fuzzAuctionStepsData_finalCheckpointsMatch(uint8 steps1, uint8 steps2) public {
        (bytes memory data1,, uint40 cumulativeBlockDelta1) = fuzzAuctionStepsData(steps1);
        (bytes memory data2,, uint40 cumulativeBlockDelta2) = fuzzAuctionStepsData(steps2);

        AuctionParameters memory params1 = params.withAuctionStepsData(data1).withStartBlock(block.number)
            .withEndBlock(block.number + cumulativeBlockDelta1)
            .withClaimBlock(block.number + cumulativeBlockDelta1 + 10);
        AuctionParameters memory params2 = params.withAuctionStepsData(data2).withStartBlock(block.number)
            .withEndBlock(block.number + cumulativeBlockDelta2)
            .withClaimBlock(block.number + cumulativeBlockDelta2 + 10);

        Auction firstAuction = new Auction(address(token), TOTAL_SUPPLY, params1);
        token.mint(address(firstAuction), TOTAL_SUPPLY);
        firstAuction.onTokensReceived();
        Auction secondAuction = new Auction(address(token), TOTAL_SUPPLY, params2);
        token.mint(address(secondAuction), TOTAL_SUPPLY);
        secondAuction.onTokensReceived();

        vm.roll(firstAuction.startBlock());
        // Submit same bid to both auctions
        uint128 inputAmount = inputAmountForTokens(1000e18, tickNumberToPriceX96(2));
        firstAuction.submitBid{value: inputAmount}(
            tickNumberToPriceX96(2), inputAmount, alice, tickNumberToPriceX96(1), bytes('')
        );
        secondAuction.submitBid{value: inputAmount}(
            tickNumberToPriceX96(2), inputAmount, alice, tickNumberToPriceX96(1), bytes('')
        );

        vm.roll(firstAuction.endBlock());
        Checkpoint memory finalCheckpoint1 = firstAuction.checkpoint();
        ValueX7 currencyRaisedQ96_X7_1 = firstAuction.currencyRaisedQ96_X7();
        vm.roll(secondAuction.endBlock());
        Checkpoint memory finalCheckpoint2 = secondAuction.checkpoint();
        ValueX7 currencyRaisedQ96_X7_2 = secondAuction.currencyRaisedQ96_X7();

        // Both auctions should have sold the TOTAL_SUPPLY at the same clearing price, and the same cumulative mps
        assertEq(finalCheckpoint1.cumulativeMps, finalCheckpoint2.cumulativeMps);
        assertEq(currencyRaisedQ96_X7_1, currencyRaisedQ96_X7_2);
        assertEq(finalCheckpoint1.clearingPrice, finalCheckpoint2.clearingPrice);
    }

    function test_stepsDataEndingWithZeroMps_succeeds(uint128 _totalSupply, uint128 _bidAmount, uint256 _maxPrice)
        public
        givenValidMaxPrice(_maxPrice, _totalSupply)
        givenValidBidAmount(_bidAmount)
        givenFullyFundedAccount
    {
        vm.assume(_totalSupply > 0);
        vm.assume($bidAmount >= uint256(_totalSupply).fullMulDivUp($maxPrice, FixedPoint96.Q96));
        uint256 startBlock = block.number;
        uint256 endBlock = startBlock + 2e7;
        uint256 claimBlock = endBlock + 10;
        AuctionParameters memory params = params.withAuctionStepsData(
                AuctionStepsBuilder.init().addStep(1, 1e7).addStep(0, 1e7)
            ).withStartBlock(startBlock).withEndBlock(endBlock).withClaimBlock(claimBlock);

        Auction newAuction = new Auction(address(token), _totalSupply, params);
        token.mint(address(newAuction), _totalSupply);
        newAuction.onTokensReceived();

        vm.roll(startBlock);
        uint256 bidId =
            newAuction.submitBid{value: $bidAmount}($maxPrice, $bidAmount, alice, tickNumberToPriceX96(1), bytes(''));

        // Show you can checkpoint when the step is zero mps
        vm.roll(startBlock + 1e7 + 1);
        Checkpoint memory checkpoint = newAuction.checkpoint();
        ValueX7 oldCurrencyRaisedQ96_X7 = newAuction.currencyRaisedQ96_X7();
        assertEq(checkpoint.cumulativeMps, 1e7);

        // The auction has fully sold out 1e7 mps worth of tokens, so all future bids will revert
        vm.expectRevert(IAuction.AuctionSoldOut.selector);
        newAuction.submitBid{value: $bidAmount}($maxPrice, $bidAmount, alice, tickNumberToPriceX96(1), bytes(''));

        vm.roll(endBlock);
        {
            Checkpoint memory finalCheckpoint = newAuction.checkpoint();
            // Assert that values in the final checkpoint is the same as the checkpoint after selling 1e7 mps worth of tokens
            assertEq(finalCheckpoint.cumulativeMps, checkpoint.cumulativeMps);
            assertEq(finalCheckpoint.clearingPrice, checkpoint.clearingPrice);
            assertEq(newAuction.currencyRaisedQ96_X7(), oldCurrencyRaisedQ96_X7);
            assertEq(
                finalCheckpoint.currencyRaisedAtClearingPriceQ96_X7, checkpoint.currencyRaisedAtClearingPriceQ96_X7
            );
            assertEq(finalCheckpoint.cumulativeMpsPerPrice, checkpoint.cumulativeMpsPerPrice);

            // Don't check mps, prev, and next because they will be different

            if ($maxPrice > finalCheckpoint.clearingPrice) {
                newAuction.exitBid(bidId);
            } else {
                newAuction.exitPartiallyFilledBid(bidId, 1, 0);
            }
        }

        vm.roll(claimBlock);
        newAuction.claimTokens(bidId);
        assertEq(token.balanceOf(address(alice)), _totalSupply);

        newAuction.sweepCurrency();
        newAuction.sweepUnsoldTokens();
    }
}
