// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Auction} from '../src/Auction.sol';
import {AuctionParameters} from '../src/interfaces/IAuction.sol';
import {AuctionStepLib} from '../src/libraries/AuctionStepLib.sol';
import {Checkpoint} from '../src/libraries/CheckpointLib.sol';
import {AuctionBaseTest} from './utils/AuctionBaseTest.sol';
import {AuctionParamsBuilder} from './utils/AuctionParamsBuilder.sol';
import {AuctionStepsBuilder} from './utils/AuctionStepsBuilder.sol';
import {Test} from 'forge-std/Test.sol';
import {console2} from 'forge-std/console2.sol';

// Test which deploys multiple auctions with similar steps data such that the end result is the same for each auction
contract AuctionStepDiffTest is AuctionBaseTest {
    using AuctionParamsBuilder for AuctionParameters;
    using AuctionStepsBuilder for bytes;

    function setUp() public {
        setUpTokens();
        alice = makeAddr('alice');
        tokensRecipient = makeAddr('tokensRecipient');
        fundsRecipient = makeAddr('fundsRecipient');

        params = AuctionParamsBuilder.init().withCurrency(ETH_SENTINEL).withFloorPrice(FLOOR_PRICE).withTickSpacing(
            TICK_SPACING
        ).withValidationHook(address(0)).withTokensRecipient(tokensRecipient).withFundsRecipient(fundsRecipient)
            .withStartBlock(block.number).withEndBlock(block.number + AUCTION_DURATION).withClaimBlock(
            block.number + AUCTION_DURATION + 10
        );
    }

    function fuzzAuctionStepsData(uint8 steps) public view returns (bytes memory, uint24, uint40) {
        vm.assume(steps > 0);
        bytes memory data = AuctionStepsBuilder.init();
        uint24 cumulativeMps = 0;
        uint40 cumulativeBlockDelta = 0;
        // Assumes block delta is 1 for simplicity
        for (uint8 i = 0; i < steps && cumulativeMps < AuctionStepLib.MPS; i++) {
            uint24 fuzzMps;
            // Bias towards 0
            if (i % 2 == 0) {
                fuzzMps = 0;
            } else {
                fuzzMps = uint24(bound(uint256(keccak256(abi.encode(i))), 0, AuctionStepLib.MPS - cumulativeMps));
            }
            // If the total mps is greater than the max mps, set the mps to the max mps and the block delta to 1
            if (fuzzMps > AuctionStepLib.MPS - cumulativeMps) {
                fuzzMps = AuctionStepLib.MPS - cumulativeMps;
            }
            cumulativeMps += fuzzMps;
            cumulativeBlockDelta++;
            data = data.addStep(fuzzMps, 1);
        }
        if (cumulativeMps < AuctionStepLib.MPS) {
            data = data.addStep(uint24(AuctionStepLib.MPS - cumulativeMps), 1);
            cumulativeMps = AuctionStepLib.MPS;
            cumulativeBlockDelta++;
        }
        assertEq(cumulativeMps, AuctionStepLib.MPS, 'fuzzed cumulative mps is not equal to the max mps');
        return (data, cumulativeMps, cumulativeBlockDelta);
    }

    function test_fuzzAuctionStepsData_finalCheckpointsMatch(uint8 steps1, uint8 steps2) public {
        (bytes memory data1,, uint40 cumulativeBlockDelta1) = fuzzAuctionStepsData(steps1);
        (bytes memory data2,, uint40 cumulativeBlockDelta2) = fuzzAuctionStepsData(steps2);

        AuctionParameters memory params1 = params.withAuctionStepsData(data1).withStartBlock(block.number).withEndBlock(
            block.number + cumulativeBlockDelta1
        );
        AuctionParameters memory params2 = params.withAuctionStepsData(data2).withStartBlock(block.number).withEndBlock(
            block.number + cumulativeBlockDelta2
        );

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
            tickNumberToPriceX96(2), true, inputAmount, alice, tickNumberToPriceX96(1), bytes('')
        );
        secondAuction.submitBid{value: inputAmount}(
            tickNumberToPriceX96(2), true, inputAmount, alice, tickNumberToPriceX96(1), bytes('')
        );

        vm.roll(firstAuction.endBlock());
        Checkpoint memory finalCheckpoint1 = firstAuction.checkpoint();
        vm.roll(secondAuction.endBlock());
        Checkpoint memory finalCheckpoint2 = secondAuction.checkpoint();

        // Both auctions should have sold the TOTAL_SUPPLY at the same clearing price, and the same cumulative mps
        assertEq(finalCheckpoint1.cumulativeMps, finalCheckpoint2.cumulativeMps);
        assertEq(finalCheckpoint1.totalCleared, finalCheckpoint2.totalCleared);
        assertEq(finalCheckpoint1.clearingPrice, finalCheckpoint2.clearingPrice);
    }
}
