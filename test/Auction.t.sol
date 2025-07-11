// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Auction, AuctionParameters} from '../src/Auction.sol';
import {IAuction} from '../src/interfaces/IAuction.sol';
import {ITickStorage} from '../src/interfaces/ITickStorage.sol';
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

        // 100 bps each block, 50 blocks each, so 5_000 bps per "step"
        bytes memory auctionStepsData = AuctionStepsBuilder.init().addStep(100, 50).addStep(100, 50);
        AuctionParameters memory params = AuctionParamsBuilder.init().withCurrency(address(currency)).withToken(
            address(token)
        ).withTotalSupply(TOTAL_SUPPLY).withFloorPrice(FLOOR_PRICE).withTickSpacing(TICK_SPACING).withValidationHook(
            address(0)
        ).withTokensRecipient(tokensRecipient).withFundsRecipient(fundsRecipient).withStartBlock(block.number)
            .withEndBlock(block.number + AUCTION_DURATION).withClaimBlock(block.number + AUCTION_DURATION)
            .withAuctionStepsData(auctionStepsData);

        // Expect the floor price tick to be initialized
        vm.expectEmit(true, true, true, true);
        emit ITickStorage.TickInitialized(1, _tickPriceAt(1));
        auction = new Auction(params);
    }

    function test_submitBid_exactIn_atFloorPrice_succeeds() public {
        vm.expectEmit(true, true, true, true);
        emit IAuction.BidSubmitted(1, _tickPriceAt(1), true, 100e18);
        auction.submitBid(_tickPriceAt(1), true, 100e18, alice, 0);
        vm.snapshotGasLastCall('submitBid_recordStep');

        auction.submitBid(_tickPriceAt(1), true, 100e18, alice, 0);
        vm.snapshotGasLastCall('submitBid');
    }

    function test_submitBid_exactOut_atFloorPrice_succeeds() public {
        vm.expectEmit(true, true, true, true);
        emit IAuction.BidSubmitted(1, _tickPriceAt(1), false, 10e18);
        auction.submitBid(_tickPriceAt(1), false, 10e18, alice, 0);
    }

    function test_submitBid_exactIn_initializesTickAndUpdatesClearingPrice_succeeds() public {
        uint256 expectedTotalCleared = 10e18; // 100 bps * total supply (1000e18)
        uint16 expectedCumulativeBps = 100; // 100 bps * 1 block
        vm.expectEmit(true, true, true, true);
        emit IAuction.CheckpointUpdated(block.number, _tickPriceAt(2), expectedTotalCleared, expectedCumulativeBps);
        vm.expectEmit(true, true, true, true);
        emit IAuction.BidSubmitted(2, _tickPriceAt(2), true, 100e18);
        auction.submitBid(_tickPriceAt(2), true, 100e18, alice, 1);
        vm.snapshotGasLastCall('submitBid_recordStep_initializeTick_updateClearingPrice');
    }

    function test_submitBid_exactOut_initializesTickAndUpdatesClearingPrice_succeeds() public {
        uint256 expectedTotalCleared = 10e18; // 100 bps * total supply (1000e18)
        uint16 expectedCumulativeBps = 100; // 100 bps * 1 block
        vm.expectEmit(true, true, true, true);
        emit IAuction.CheckpointUpdated(block.number, _tickPriceAt(2), expectedTotalCleared, expectedCumulativeBps);
        vm.expectEmit(true, true, true, true);
        emit IAuction.BidSubmitted(2, _tickPriceAt(2), false, 10e18);
        auction.submitBid(_tickPriceAt(2), false, 10e18, alice, 1);
    }

    function test_submitBid_updatesClearingPrice_succeeds() public {
        uint256 expectedTotalCleared = 10e18; // 100 bps * total supply (1000e18)
        uint16 expectedCumulativeBps = 100; // 100 bps * 1 block
        vm.expectEmit(true, true, true, true);
        emit IAuction.CheckpointUpdated(block.number, _tickPriceAt(2), expectedTotalCleared, expectedCumulativeBps);
        // Bid enough to update the clearing price
        auction.submitBid(_tickPriceAt(2), true, 500e18, alice, 1);
    }

    function test_submitBid_multipleTicks_succeeds() public {
        vm.expectEmit(true, true, true, true);
        emit ITickStorage.TickInitialized(2, _tickPriceAt(2));
        auction.submitBid(_tickPriceAt(2), true, 500e18, alice, 1);
        vm.snapshotGasLastCall('submitBid_recordStep_initializeTick');

        vm.expectEmit(true, true, true, true);
        emit ITickStorage.TickInitialized(3, _tickPriceAt(3));
        auction.submitBid(_tickPriceAt(3), true, 500e18, alice, 2);
        vm.snapshotGasLastCall('submitBid_initializeTick');
    }
}
