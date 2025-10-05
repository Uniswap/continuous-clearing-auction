// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Auction} from '../../src/Auction.sol';
import {Tick} from '../../src/TickStorage.sol';
import {AuctionParameters, IAuction} from '../../src/interfaces/IAuction.sol';
import {ITickStorage} from '../../src/interfaces/ITickStorage.sol';
import {BidLib} from '../../src/libraries/BidLib.sol';
import {FixedPoint96} from '../../src/libraries/FixedPoint96.sol';
import {Assertions} from './Assertions.sol';
import {AuctionParamsBuilder} from './AuctionParamsBuilder.sol';
import {AuctionStepsBuilder} from './AuctionStepsBuilder.sol';
import {MockFundsRecipient} from './MockFundsRecipient.sol';
import {MockToken} from './MockToken.sol';
import {TokenHandler} from './TokenHandler.sol';
import {Test} from 'forge-std/Test.sol';
import {FixedPointMathLib} from 'solady/utils/FixedPointMathLib.sol';

/// @notice Handler contract for setting up an auction
abstract contract AuctionBaseTest is TokenHandler, Assertions, Test {
    using FixedPointMathLib for uint256;
    using AuctionParamsBuilder for AuctionParameters;
    using AuctionStepsBuilder for bytes;

    Auction public auction;

    uint256 public constant AUCTION_DURATION = 100;
    uint256 public constant TICK_SPACING = 100 << FixedPoint96.RESOLUTION;
    uint256 public constant FLOOR_PRICE = 1000 << FixedPoint96.RESOLUTION;
    uint256 public constant TOTAL_SUPPLY = 1000e18;

    // Max amount of wei that can be lost in totalClearedX7X7 calculations
    uint256 public constant MAX_TOTAL_CLEARED_PRECISION_LOSS = 1;

    address public alice;
    address public bob;
    address public tokensRecipient;
    address public fundsRecipient;
    MockFundsRecipient public mockFundsRecipient;

    AuctionParameters public params;
    bytes public auctionStepsData;

    uint256 public $bidAmount;

    function setUpAuction() public {
        setUpTokens();

        alice = makeAddr('alice');
        bob = makeAddr('bob');
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

    function helper__deployAuctionWithFailingToken() internal returns (Auction) {
        MockToken failingToken = new MockToken();

        bytes memory failingAuctionStepsData = AuctionStepsBuilder.init().addStep(100e3, 100);
        AuctionParameters memory failingParams = AuctionParamsBuilder.init().withCurrency(ETH_SENTINEL).withFloorPrice(
            FLOOR_PRICE
        ).withTickSpacing(TICK_SPACING).withValidationHook(address(0)).withTokensRecipient(tokensRecipient)
            .withFundsRecipient(fundsRecipient).withStartBlock(block.number).withEndBlock(block.number + AUCTION_DURATION)
            .withClaimBlock(block.number + AUCTION_DURATION + 10).withAuctionStepsData(failingAuctionStepsData);

        Auction failingAuction = new Auction(address(failingToken), TOTAL_SUPPLY, failingParams);
        failingToken.mint(address(failingAuction), TOTAL_SUPPLY);
        failingAuction.onTokensReceived();

        return failingAuction;
    }

    function helper__roundPriceDownToTickSpacing(uint256 _price, uint256 _tickSpacing)
        internal
        pure
        returns (uint256)
    {
        return _price - (_price % _tickSpacing);
    }

    modifier givenGraduatedAuction(uint256 _bidAmount) {
        $bidAmount = _bound(_bidAmount, TOTAL_SUPPLY, type(uint128).max);
        _;
    }

    modifier givenNotGraduatedAuction(uint256 _bidAmount) {
        // TODO(ez): some rounding in auction preventing this from being TOTAL_SUPPLY - 1
        $bidAmount = _bound(_bidAmount, 1, TOTAL_SUPPLY / 2);
        _;
    }

    modifier givenFullyFundedAccount() {
        vm.deal(address(this), type(uint256).max);
        _;
    }

    /// @dev Helper function to convert a tick number to a priceX96
    function tickNumberToPriceX96(uint256 tickNumber) internal pure returns (uint256) {
        return FLOOR_PRICE + (tickNumber - 1) * TICK_SPACING;
    }

    /// @dev Helper function to get price of a tick above floor price
    function tickNumberToPriceAboveFloorX96(uint256 tickNumber, uint256 floorPrice, uint256 tickSpacing)
        internal
        pure
        returns (uint256)
    {
        return ((floorPrice + (tickNumber * tickSpacing)) / tickSpacing) * tickSpacing;
    }

    /// Return the inputAmount required to purchase at least the given number of tokens at the given maxPrice
    function inputAmountForTokens(uint256 tokens, uint256 maxPrice) internal pure returns (uint256) {
        return tokens.fullMulDivUp(maxPrice, FixedPoint96.Q96);
    }

    /// @notice Helper function to return the tick at the given price
    function getTick(uint256 price) public view returns (Tick memory) {
        return auction.ticks(price);
    }
}
