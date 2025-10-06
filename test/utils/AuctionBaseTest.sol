// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Auction} from '../../src/Auction.sol';

import {Checkpoint} from '../../src/CheckpointStorage.sol';
import {Tick} from '../../src/TickStorage.sol';
import {AuctionParameters, IAuction} from '../../src/interfaces/IAuction.sol';
import {ITickStorage} from '../../src/interfaces/ITickStorage.sol';
import {BidLib} from '../../src/libraries/BidLib.sol';
import {ConstantsLib} from '../../src/libraries/ConstantsLib.sol';
import {FixedPoint96} from '../../src/libraries/FixedPoint96.sol';
import {SupplyLib} from '../../src/libraries/SupplyLib.sol';
import {ValueX7, ValueX7Lib} from '../../src/libraries/ValueX7Lib.sol';
import {Assertions} from './Assertions.sol';
import {AuctionParamsBuilder} from './AuctionParamsBuilder.sol';
import {AuctionStepsBuilder} from './AuctionStepsBuilder.sol';
import {FuzzBid, FuzzDeploymentParams} from './FuzzStructs.sol';
import {MockFundsRecipient} from './MockFundsRecipient.sol';

import {MockToken} from './MockToken.sol';
import {TickBitmap, TickBitmapLib} from './TickBitmap.sol';
import {TokenHandler} from './TokenHandler.sol';
import {Test} from 'forge-std/Test.sol';
import {console} from 'forge-std/console.sol';
import {FixedPointMathLib} from 'solady/utils/FixedPointMathLib.sol';
/// @notice Handler contract for setting up an auction

abstract contract AuctionBaseTest is TokenHandler, Assertions, Test {
    using FixedPointMathLib for uint256;
    using AuctionParamsBuilder for AuctionParameters;
    using AuctionStepsBuilder for bytes;
    using TickBitmapLib for TickBitmap;
    using ValueX7Lib for *;

    TickBitmap private tickBitmap;

    Auction public auction;

    uint256 public constant AUCTION_DURATION = 100;
    uint256 public constant TICK_SPACING = 100 << FixedPoint96.RESOLUTION;
    uint256 public constant FLOOR_PRICE = 1000 << FixedPoint96.RESOLUTION;
    uint128 public constant TOTAL_SUPPLY = 1000e18;

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
    uint256 public $maxPrice;

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
        vm.assume(_deploymentParams.totalSupply > 0);

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
        vm.assume(ConstantsLib.MPS % _deploymentParams.numberOfSteps == 0); // such that it is divisible

        // TODO(md): fix and have variation in the step sizes

        // Replace auction steps data with a valid one
        // Divide steps by number of bips
        uint256 _numberOfMps = ConstantsLib.MPS / _deploymentParams.numberOfSteps;
        bytes memory _auctionStepsData = new bytes(0);
        for (uint8 i = 0; i < _deploymentParams.numberOfSteps; i++) {
            _auctionStepsData = AuctionStepsBuilder.addStep(_auctionStepsData, uint24(_numberOfMps), uint40(1));
        }
        _deploymentParams.auctionParams.auctionStepsData = _auctionStepsData;

        return _deploymentParams.auctionParams;
    }

    function helper__goToAuctionStartBlock() public {
        vm.roll(auction.startBlock());
    }

    function helper__roundPriceDownToTickSpacing(uint256 _price, uint256 _tickSpacing)
        internal
        pure
        returns (uint256)
    {
        return _price - (_price % _tickSpacing);
    }

    function helper__roundPriceUpToTickSpacing(uint256 _price, uint256 _tickSpacing) internal pure returns (uint256) {
        uint256 remainder = _price % _tickSpacing;
        if (remainder != 0) {
            require(
                _price <= type(uint256).max - (_tickSpacing - remainder),
                'helper__roundPriceUpToTickSpacing: Price would overflow uint256'
            );
            return _price + (_tickSpacing - remainder);
        }
        return _price;
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

        maxPrice = _bound(maxPrice, tickAboveFloorPrice, uint256(type(uint256).max));
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
        // if the bid is above the max price, don't submit the bid
        if (maxPrice >= BidLib.MAX_BID_PRICE) return (false, 0);
        // if the bid if not above the clearing price, don't submit the bid
        if (maxPrice <= clearingPrice) return (false, 0);
        // If the bid would overflow a ValueX7X7 value, don't submit the bid
        if (_bid.bidAmount > BidLib.MAX_BID_AMOUNT / maxPrice) return (false, 0);

        uint256 ethInputAmount = inputAmountForTokens(_bid.bidAmount, maxPrice);

        // Get the correct last tick price for the bid
        uint256 lowerTickNumber = tickBitmap.findPrev(_bid.tickNumber);
        uint256 lastTickPrice = helper__maxPriceMultipleOfTickSpacingAboveFloorPrice(lowerTickNumber);

        vm.expectEmit(true, true, true, true);
        emit IAuction.BidSubmitted(_i, _owner, maxPrice, ethInputAmount);
        try auction.submitBid{value: ethInputAmount}(maxPrice, ethInputAmount, _owner, lastTickPrice, bytes(''))
        returns (uint256 _bidId) {
            bidId = _bidId;
        } catch (bytes memory revertData) {
            // Ok if the bid price is invalid IF it just moved this block
            if (bytes4(revertData) == IAuction.InvalidBidPrice.selector) {
                Checkpoint memory checkpoint = auction.checkpoint();
                // the bid price is invalid as it is less than or equal to the clearing price
                // skip the test by returning false and 0
                if (maxPrice <= checkpoint.clearingPrice) return (false, 0);
                revert('Uncaught InvalidBidPrice');
            }
            // Otherwise, treat as uncaught error
            assembly {
                revert(add(revertData, 0x20), mload(revertData))
            }
        }

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

    function helper__toDemand(FuzzBid memory _bid, uint24 _startCumulativeMps)
        internal
        pure
        returns (ValueX7 currencyDemandX7)
    {
        currencyDemandX7 =
            _bid.bidAmount.scaleUpToX7().mulUint256(ConstantsLib.MPS).divUint256(ConstantsLib.MPS - _startCumulativeMps);
    }

    /// @dev All bids provided to bid fuzz must have some value and a positive tick number
    modifier setUpBidsFuzz(FuzzBid[] memory _bids) {
        for (uint256 i = 0; i < _bids.length; i++) {
            // Note(md): errors when bumped to uint128
            _bids[i].bidAmount = uint64(_bound(_bids[i].bidAmount, BidLib.MIN_BID_AMOUNT, type(uint64).max));
            _bids[i].tickNumber = uint8(_bound(_bids[i].tickNumber, 1, type(uint8).max));
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

    // Non fuzzing variant of setUpAuction
    function setUpAuction() public requireAuctionNotSetup {
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

    function helper_getMaxBidAmountAtMaxPrice() internal view returns (uint256) {
        require($maxPrice > 0, 'Max price is not set in test yet');
        return BidLib.MAX_BID_AMOUNT / $maxPrice;
    }

    modifier givenValidMaxPrice(uint256 _maxPrice) {
        _maxPrice = _bound(_maxPrice, FLOOR_PRICE, BidLib.MAX_BID_PRICE);
        _maxPrice = helper__roundPriceDownToTickSpacing(_maxPrice, TICK_SPACING);
        vm.assume(_maxPrice > FLOOR_PRICE);
        $maxPrice = _maxPrice;
        _;
    }

    modifier givenValidBidAmount(uint256 _bidAmount) {
        if (BidLib.MIN_BID_AMOUNT <= helper_getMaxBidAmountAtMaxPrice()) {
            $bidAmount = BidLib.MIN_BID_AMOUNT;
        } else {
            vm.assume(BidLib.MIN_BID_AMOUNT < helper_getMaxBidAmountAtMaxPrice());
            $bidAmount = _bound(_bidAmount, BidLib.MIN_BID_AMOUNT, helper_getMaxBidAmountAtMaxPrice());
        }
        _;
    }

    modifier givenGraduatedAuction() {
        if (TOTAL_SUPPLY <= helper_getMaxBidAmountAtMaxPrice()) {
            $bidAmount = TOTAL_SUPPLY;
        } else {
            vm.assume(TOTAL_SUPPLY < helper_getMaxBidAmountAtMaxPrice());
            $bidAmount = _bound($bidAmount, TOTAL_SUPPLY, helper_getMaxBidAmountAtMaxPrice());
        }
        _;
    }

    modifier givenNotGraduatedAuction(uint256 _bidAmount) {
        // TODO(ez): some rounding in auction preventing this from being TOTAL_SUPPLY - 1
        $bidAmount = _bound(_bidAmount, BidLib.MIN_BID_AMOUNT, TOTAL_SUPPLY / 2);
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
