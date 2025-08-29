// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Auction} from '../src/Auction.sol';
import {AuctionParameters} from '../src/interfaces/IAuction.sol';
import {ITickStorage} from '../src/interfaces/ITickStorage.sol';
import {FixedPoint96} from '../src/libraries/FixedPoint96.sol';
import {Currency} from '../src/libraries/CurrencyLibrary.sol';
import {AuctionBaseTest} from './utils/AuctionBaseTest.sol';
import {AuctionParamsBuilder} from './utils/AuctionParamsBuilder.sol';
import {AuctionStepsBuilder} from './utils/AuctionStepsBuilder.sol';
import {MockFundsRecipient} from './utils/MockFundsRecipient.sol';
import {TokenHandler} from './utils/TokenHandler.sol';
import {Test} from 'forge-std/Test.sol';

contract AuctionNativeCurrencyTest is AuctionBaseTest {
    using AuctionParamsBuilder for AuctionParameters;
    using AuctionStepsBuilder for bytes;

    constructor() AuctionBaseTest(100, 100, 1000 << FixedPoint96.RESOLUTION, 1000e18) {}

    function _createAuction() internal override returns (Auction) {
        alice = makeAddr('alice');
        tokensRecipient = makeAddr('tokensRecipient');
        fundsRecipient = makeAddr('fundsRecipient');
        mockFundsRecipient = new MockFundsRecipient();

        auctionStepsData = AuctionStepsBuilder.init().addStep(100e3, 50).addStep(100e3, 50);
        params = AuctionParamsBuilder.init().withCurrency(address(currency)).withFloorPrice(FLOOR_PRICE).withTickSpacing(
            TICK_SPACING
        ).withValidationHook(address(0)).withTokensRecipient(tokensRecipient).withFundsRecipient(fundsRecipient)
            .withStartBlock(block.number).withEndBlock(block.number + AUCTION_DURATION).withClaimBlock(
            block.number + AUCTION_DURATION + 10
        ).withAuctionStepsData(auctionStepsData);

        // Expect the floor price tick to be initialized
        vm.expectEmit(true, true, true, true);
        emit ITickStorage.TickInitialized(tickNumberToPriceX96(1));
        Auction nativeCurrencyAuction = new Auction(address(token), TOTAL_SUPPLY, params);

        token.mint(address(nativeCurrencyAuction), TOTAL_SUPPLY);
        currency.mint(alice, type(uint128).max);

        return nativeCurrencyAuction;
    }
}
