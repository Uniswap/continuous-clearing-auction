// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Auction} from '../../src/Auction.sol';
import {Tick} from '../../src/TickStorage.sol';
import {AuctionParameters, IAuction} from '../../src/interfaces/IAuction.sol';
import {ITickStorage} from '../../src/interfaces/ITickStorage.sol';
import {Demand} from '../../src/libraries/DemandLib.sol';
import {FixedPoint96} from '../../src/libraries/FixedPoint96.sol';
import {MPSLib} from '../../src/libraries/MPSLib.sol';
import {SupplyLib} from '../../src/libraries/SupplyLib.sol';
import {Assertions} from './Assertions.sol';
import {AuctionParamsBuilder} from './AuctionParamsBuilder.sol';
import {AuctionStepsBuilder} from './AuctionStepsBuilder.sol';
import {FuzzBid, FuzzDeploymentParams} from './FuzzStructs.sol';
import {MockFundsRecipient} from './MockFundsRecipient.sol';
import {TokenHandler} from './TokenHandler.sol';
import {Test} from 'forge-std/Test.sol';
import {FixedPointMathLib} from 'solady/utils/FixedPointMathLib.sol';
import {TickBitmap, TickBitmapLib} from './TickBitmap.sol';

/// @notice Handler contract for setting up an auction
abstract contract AuctionBaseTest is TokenHandler, Assertions, Test {
    using FixedPointMathLib for uint256;
    using AuctionParamsBuilder for AuctionParameters;
    using AuctionStepsBuilder for bytes;
    using TickBitmapLib for TickBitmap;

    bool internal $exactIn = true;
    TickBitmap private tickBitmap;

    Auction public auction;

    uint256 public constant AUCTION_DURATION = 100;
    uint256 public constant TICK_SPACING = 100 << FixedPoint96.RESOLUTION;
    uint256 public constant FLOOR_PRICE = 1000 << FixedPoint96.RESOLUTION;
    uint256 public constant TOTAL_SUPPLY = 1000e18;

    address public alice;
    address public tokensRecipient;
    address public fundsRecipient;
    MockFundsRecipient public mockFundsRecipient;

    AuctionParameters public params;
    bytes public auctionStepsData;

    function helper__validFuzzDeploymentParams(FuzzDeploymentParams memory _deploymentParams)
        public
        view
        returns (AuctionParameters memory)
    {
        // Hard coded for tests
        _deploymentParams.auctionParams.currency = ETH_SENTINEL;
        _deploymentParams.auctionParams.tokensRecipient = tokensRecipient;
        _deploymentParams.auctionParams.fundsRecipient = fundsRecipient;
        _deploymentParams.auctionParams.validationHook = address(0);

        _deploymentParams.totalSupply = _bound(_deploymentParams.totalSupply, 1, SupplyLib.MAX_TOTAL_SUPPLY);

        // -2 because we need to account for the endBlock and claimBlock
        _deploymentParams.auctionParams.startBlock = uint64(
            _bound(
                _deploymentParams.auctionParams.startBlock,
                block.number,
                type(uint64).max - _deploymentParams.numberOfSteps - 2
            )
        );
        _deploymentParams.auctionParams.endBlock =
            _deploymentParams.auctionParams.startBlock + uint64(_deploymentParams.numberOfSteps);
        _deploymentParams.auctionParams.claimBlock = _deploymentParams.auctionParams.endBlock + 1;

        vm.assume(_deploymentParams.auctionParams.graduationThresholdMps != 0);

        // Dont have tick spacing or floor price too large
        _deploymentParams.auctionParams.floorPrice =
            _bound(_deploymentParams.auctionParams.floorPrice, 0, type(uint128).max);
        _deploymentParams.auctionParams.tickSpacing =
            _bound(_deploymentParams.auctionParams.tickSpacing, 0, type(uint128).max);

        // first assume that tick spacing is not zero to avoid division by zero
        vm.assume(_deploymentParams.auctionParams.tickSpacing != 0);
        // round down to the closest floor price to the tick spacing
        _deploymentParams.auctionParams.floorPrice = _deploymentParams.auctionParams.floorPrice
            / _deploymentParams.auctionParams.tickSpacing * _deploymentParams.auctionParams.tickSpacing;
        // then assume that floor price is non zero
        vm.assume(_deploymentParams.auctionParams.floorPrice != 0);

        vm.assume(_deploymentParams.numberOfSteps > 0);
        vm.assume(MPSLib.MPS % _deploymentParams.numberOfSteps == 0); // such that it is divisible

        // TODO(md): fix and have variation in the step sizes

        // Replace auction steps data with a valid one
        // Divide steps by number of bips
        uint256 _numberOfMps = MPSLib.MPS / _deploymentParams.numberOfSteps;
        bytes memory _auctionStepsData = new bytes(0);
        for (uint8 i = 0; i < _deploymentParams.numberOfSteps; i++) {
            _auctionStepsData = AuctionStepsBuilder.addStep(_auctionStepsData, uint24(_numberOfMps), uint40(1));
        }
        _deploymentParams.auctionParams.auctionStepsData = _auctionStepsData;

        // Bound graduation threshold mps
        _deploymentParams.auctionParams.graduationThresholdMps =
            uint24(bound(_deploymentParams.auctionParams.graduationThresholdMps, 0, uint24(MPSLib.MPS)));

        return _deploymentParams.auctionParams;
    }

    function helper__goToAuctionStartBlock() public {
        vm.roll(auction.startBlock());
    }

    /// @dev Given a tick number, return it as a multiple of the tick spacing above the floor price - as q96
    function helper__maxPriceMultipleOfTickSpacingAboveFloorPrice(uint256 _tickNumber)
        internal
        view
        returns (uint256 maxPriceQ96)
    {
        uint256 tickSpacing = params.tickSpacing;
        uint256 floorPrice = params.floorPrice;

        if (_tickNumber == 0) return floorPrice;

        uint256 maxPrice = ((floorPrice + (_tickNumber * tickSpacing)) / tickSpacing) * tickSpacing;

        // Find the first value above floorPrice that is a multiple of tickSpacing
        uint256 tickAboveFloorPrice = ((floorPrice / tickSpacing) + 1) * tickSpacing;

        maxPrice = bound(maxPrice, tickAboveFloorPrice, uint256(type(uint256).max));
        maxPriceQ96 = maxPrice << FixedPoint96.RESOLUTION;
    }

    /// @dev Submit a bid for a given tick number, amount, and owner
    /// @dev if the bid was not successfully placed - i.e. it would not have succeeded at clearing - bidPlaced is false and bidId is 0
    function helper__trySubmitBid(uint256 _i, FuzzBid memory _bid, address _owner)
        internal
        returns (bool bidPlaced, uint256 bidId)
    {
        uint256 clearingPrice = auction.clearingPrice();

        // Get the correct bid prices for the bid
        uint256 maxPrice = helper__maxPriceMultipleOfTickSpacingAboveFloorPrice(_bid.tickNumber);

        // if the bid if not above the clearing price, don't submit the bid
        if (maxPrice <= clearingPrice) return (false, 0);

        uint256 ethInputAmount = inputAmountForTokens(_bid.bidAmount, maxPrice);

        // Get the correct last tick price for the bid
        uint256 lowerTickNumber = tickBitmap.findPrev(_bid.tickNumber);
        uint256 lastTickPrice = helper__maxPriceMultipleOfTickSpacingAboveFloorPrice(lowerTickNumber);

        vm.expectEmit(true, true, true, true);
        emit IAuction.BidSubmitted(_i, _owner, maxPrice, $exactIn, $exactIn ? ethInputAmount : _bid.bidAmount);
        bidId = auction.submitBid{value: ethInputAmount}(
            maxPrice,
            $exactIn,
            // if the bid is exact in, use the eth input amount, otherwise use the bid amount in tokens
            $exactIn ? ethInputAmount : _bid.bidAmount,
            _owner,
            lastTickPrice,
            bytes('')
        );

        // Set the tick in the bitmap for future bids
        tickBitmap.set(_bid.tickNumber);

        return (true, bidId);
    }

    /// @dev if iteration block has bottom two bits set, roll to the next block - 25% chance
    function helper__maybeRollToNextBlock(uint256 _iteration) internal {
        uint256 endBlock = auction.endBlock();

        uint256 rand = uint256(keccak256(abi.encode(block.prevrandao, _iteration)));
        bool rollToNextBlock = rand & 0x3 == 0;
        // Randomly roll to the next block
        if (rollToNextBlock && block.number < endBlock - 1) {
            vm.roll(block.number + 1);
        }
    }

    /// @dev All bids provided to bid fuzz must have some value and a positive tick number
    modifier setUpBidsFuzz(FuzzBid[] memory _bids) {
        for (uint256 i = 0; i < _bids.length; i++) {
            // Note(md): errors when bumped to uint128
            _bids[i].bidAmount = uint64(bound(_bids[i].bidAmount, 1, type(uint64).max));
            _bids[i].tickNumber = uint8(bound(_bids[i].tickNumber, 1, type(uint8).max));
        }
        _;
    }

    modifier requireAuctionNotSetup() {
        require(address(auction) == address(0), 'Auction already setup');
        _;
    }

    // Fuzzing variant of setUpAuction
    function setUpAuction(FuzzDeploymentParams memory _deploymentParams) public requireAuctionNotSetup {
        setUpTokens();

        alice = makeAddr('alice');
        tokensRecipient = makeAddr('tokensRecipient');
        fundsRecipient = makeAddr('fundsRecipient');
        mockFundsRecipient = new MockFundsRecipient();

        params = helper__validFuzzDeploymentParams(_deploymentParams);

        // Expect the floor price tick to be initialized
        vm.expectEmit(true, true, true, true);
        emit ITickStorage.TickInitialized(_deploymentParams.auctionParams.floorPrice);
        auction = new Auction(address(token), _deploymentParams.totalSupply, params);

        token.mint(address(auction), _deploymentParams.totalSupply);
        auction.onTokensReceived();
    }

    /// @dev Sets up the auction for fuzzing, ensuring valid parameters
    modifier setUpAuctionFuzz(FuzzDeploymentParams memory _deploymentParams) {
        setUpAuction(_deploymentParams);
        _;
    }

    modifier givenAuctionHasStarted() {
        helper__goToAuctionStartBlock();
        _;
    }

    modifier givenFullyFundedAccount() {
        vm.deal(address(this), uint256(type(uint256).max));
        _;
    }

    modifier givenNonZeroTickNumber(uint8 _tickNumber) {
        vm.assume(_tickNumber > 0);
        _;
    }

    modifier givenExactIn() {
        $exactIn = true;
        _;
    }

    modifier givenExactOut() {
        $exactIn = false;
        _;
    }

    // Non fuzzing variant of setUpAuction
    function setUpAuction() public requireAuctionNotSetup {
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
        return FLOOR_PRICE + (tickNumber - 1) * TICK_SPACING;
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
