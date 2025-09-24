// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Auction} from '../../src/Auction.sol';
import {Tick} from '../../src/TickStorage.sol';
import {AuctionParameters, IAuction} from '../../src/interfaces/IAuction.sol';
import {ITickStorage} from '../../src/interfaces/ITickStorage.sol';
import {Demand} from '../../src/libraries/DemandLib.sol';
import {FixedPoint96} from '../../src/libraries/FixedPoint96.sol';
import {AuctionParamsBuilder} from './AuctionParamsBuilder.sol';
import {AuctionStepsBuilder} from './AuctionStepsBuilder.sol';

import {MockFundsRecipient} from './MockFundsRecipient.sol';
import {TokenHandler} from './TokenHandler.sol';
import {Test} from 'forge-std/Test.sol';

/// @notice Handler contract for setting up an auction
abstract contract AuctionBaseTest is TokenHandler, Test {
    using AuctionParamsBuilder for AuctionParameters;
    using AuctionStepsBuilder for bytes;

    Auction public auction;

    uint256 public constant AUCTION_DURATION = 100;
    uint256 public constant TICK_SPACING = 100;
    uint256 public constant FLOOR_PRICE = 1000 << FixedPoint96.RESOLUTION;
    uint256 public constant TOTAL_SUPPLY = 1000e18;

    address public alice;
    address public tokensRecipient;
    address public fundsRecipient;
    MockFundsRecipient public mockFundsRecipient;

    AuctionParameters public params;
    bytes public auctionStepsData;

    function setUpAuction() public {
        setUpTokens();

        alice = makeAddr('alice');
        tokensRecipient = makeAddr('tokensRecipient');
        fundsRecipient = makeAddr('fundsRecipient');
        mockFundsRecipient = new MockFundsRecipient();

        auctionStepsData = AuctionStepsBuilder.init().addStep(100e3, 50).addStep(100e3, 50);
        params = AuctionParamsBuilder.init().withCurrency(ETH_SENTINEL).withFloorPrice(FLOOR_PRICE).withTickSpacing(
            TICK_SPACING
        ).withValidationHook(address(0)).withTokensRecipient(tokensRecipient).withFundsRecipient(fundsRecipient)
            .withStartBlock(block.number).withEndBlock(block.number + AUCTION_DURATION).withClaimBlock(
            block.number + AUCTION_DURATION + 10
        ).withAuctionStepsData(auctionStepsData);

        // Expect the floor price tick to be initialized
        vm.expectEmit(true, true, true, true);
        emit ITickStorage.TickInitialized(tickNumberToPriceX96(1));
        auction = new Auction(address(token), TOTAL_SUPPLY, params);

        token.mint(address(auction), TOTAL_SUPPLY);
        // Expect the tokens to be received
        auction.onTokensReceived();
    }

    /// @dev Helper function to convert a tick number to a priceX96
    function tickNumberToPriceX96(uint256 tickNumber) internal pure returns (uint256) {
        return ((FLOOR_PRICE >> FixedPoint96.RESOLUTION) + (tickNumber - 1) * TICK_SPACING) << FixedPoint96.RESOLUTION;
    }

    /// @notice Helper function to return the tick at the given price
    function getTick(uint256 price) public view returns (Tick memory) {
        (uint256 next, Demand memory demand) = auction.ticks(price);
        return Tick({next: next, demand: demand});
    }
}
