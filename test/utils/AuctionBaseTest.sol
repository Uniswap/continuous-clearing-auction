// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Auction} from '../../src/Auction.sol';
import {AuctionParameters, IAuction} from '../../src/interfaces/IAuction.sol';

import {ITickStorage} from '../../src/interfaces/ITickStorage.sol';
import {AuctionParamsBuilder} from './AuctionParamsBuilder.sol';
import {AuctionStepsBuilder} from './AuctionStepsBuilder.sol';
import {TokenHandler} from './TokenHandler.sol';
import {Test} from 'forge-std/Test.sol';

/// @notice Handler contract for setting up an auction
abstract contract AuctionBaseTest is TokenHandler, Test {
    using AuctionParamsBuilder for AuctionParameters;
    using AuctionStepsBuilder for bytes;

    Auction public auction;

    uint256 public constant AUCTION_DURATION = 100;
    uint256 public constant TICK_SPACING = 1e6;
    uint128 public constant FLOOR_PRICE = 1e6;
    uint256 public constant TOTAL_SUPPLY = 1000e18;

    address public alice;
    address public tokensRecipient;
    address public fundsRecipient;

    function _tickPriceAt(uint128 id) internal pure returns (uint128 price) {
        require(id > 0, 'id must be greater than 0');
        return uint128(FLOOR_PRICE + (id - 1) * TICK_SPACING);
    }

    function setUpAuction() public {
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

        token.mint(address(auction), TOTAL_SUPPLY);
    }
}
