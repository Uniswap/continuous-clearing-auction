// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Test} from 'forge-std/Test.sol';
import {Auction, AuctionParameters} from '../src/Auction.sol';
import {IAuction} from '../src/interfaces/IAuction.sol';

import {IAuction} from '../src/interfaces/IAuction.sol';
import {AuctionParamsBuilder} from './utils/AuctionParamsBuilder.sol';
import {AuctionStepsBuilder} from './utils/AuctionStepsBuilder.sol';
import {TokenHandler} from './utils/TokenHandler.sol';

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

    function setUp() public {
        setUpTokens();

        alice = makeAddr('alice');
        tokensRecipient = makeAddr('tokensRecipient');
        fundsRecipient = makeAddr('fundsRecipient');

        bytes memory auctionStepsData = AuctionStepsBuilder.init().addStep(5000, 50).addStep(5000, 50);
        AuctionParameters memory params = AuctionParamsBuilder.init().withCurrency(address(currency)).withToken(
            address(token)
        ).withTotalSupply(TOTAL_SUPPLY).withFloorPrice(FLOOR_PRICE).withTickSpacing(TICK_SPACING).withValidationHook(
            address(0)
        ).withTokensRecipient(tokensRecipient).withFundsRecipient(fundsRecipient).withStartBlock(block.number)
            .withEndBlock(block.number + AUCTION_DURATION).withClaimBlock(block.number + AUCTION_DURATION)
            .withAuctionStepsData(auctionStepsData);

        // Expect the floor price tick to be initialized
        vm.expectEmit(true, true, true, true);
        emit IAuction.TickInitialized(1, FLOOR_PRICE);
        auction = new Auction(params);
    }

    function test_recordStep_afterStartBlock_succeeds() public {
        vm.expectEmit(true, true, true, true);
        emit IAuction.AuctionStepRecorded(1, block.number, block.number + 50);
        auction.recordStep();
        vm.snapshotGasLastCall('recordStep');
    }

    function test_submitBid_exactIn_atFloorPrice_succeeds() public {
        vm.expectEmit(true, true, true, true);
        emit IAuction.BidSubmitted(1, FLOOR_PRICE, true, 100e18);
        auction.submitBid(FLOOR_PRICE, true, 100e18, alice, 0);
        vm.snapshotGasLastCall('submitBid_exactIn_floorPrice');
    }

    function test_submitBid_exactOut_atFloorPrice_succeeds() public {
        vm.expectEmit(true, true, true, true);
        emit IAuction.BidSubmitted(1, FLOOR_PRICE, false, 100e18);
        auction.submitBid(FLOOR_PRICE, false, 100e18, alice, 0);
        vm.snapshotGasLastCall('submitBid_exactOut_floorPrice');
    }

    function test_submitBid_exactIn_initializesTickAndUpdatesClearingPrice_succeeds() public {
        vm.expectEmit(true, true, true, true);
        emit IAuction.TickInitialized(2, 2e18);
        vm.expectEmit(true, true, true, true);
        emit IAuction.ClearingPriceUpdated(0, FLOOR_PRICE);
        vm.expectEmit(true, true, true, true);
        emit IAuction.BidSubmitted(2, 2e18, true, 100e18);
        auction.submitBid(2e18, true, 100e18, alice, 1);
        vm.snapshotGasLastCall('submitBid_exactIn_initializesTickAndUpdatesClearingPrice');
    }

    function test_submitBid_exactOut_initializesTickAndUpdatesClearingPrice_succeeds() public {
        vm.expectEmit(true, true, true, true);
        emit IAuction.TickInitialized(2, 2e18);
        vm.expectEmit(true, true, true, true);
        emit IAuction.ClearingPriceUpdated(0, FLOOR_PRICE);
        vm.expectEmit(true, true, true, true);
        emit IAuction.BidSubmitted(2, 2e18, false, 100e18);
        auction.submitBid(2e18, false, 100e18, alice, 1);
        vm.snapshotGasLastCall('submitBid_exactOut_initializesTickAndUpdatesClearingPrice');
    }
}
