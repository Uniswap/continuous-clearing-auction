// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Checkpoint} from '../../src/CheckpointStorage.sol';
import {ContinuousClearingAuction} from '../../src/ContinuousClearingAuction.sol';
import {Tick} from '../../src/TickStorage.sol';
import {AuctionParameters, IContinuousClearingAuction} from '../../src/interfaces/IContinuousClearingAuction.sol';
import {ITickStorage} from '../../src/interfaces/ITickStorage.sol';
import {ITokenCurrencyStorage} from '../../src/interfaces/ITokenCurrencyStorage.sol';
import {BidLib} from '../../src/libraries/BidLib.sol';
import {ConstantsLib} from '../../src/libraries/ConstantsLib.sol';
import {FixedPoint96} from '../../src/libraries/FixedPoint96.sol';
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
import {SafeCastLib} from 'solady/utils/SafeCastLib.sol';

/// @notice Handler contract for setting up an auction
abstract contract AuctionBaseTest is TokenHandler, Assertions, Test {
    using FixedPointMathLib for *;
    using AuctionParamsBuilder for AuctionParameters;
    using AuctionStepsBuilder for bytes;
    using TickBitmapLib for TickBitmap;
    using ValueX7Lib for *;
    using BidLib for *;

    TickBitmap private tickBitmap;

    ContinuousClearingAuction public auction;

    // Auction configuration constants
    uint256 public constant AUCTION_DURATION = 100;
    uint256 public constant CLAIM_BLOCK_OFFSET = 10; // 10 blocks after the auction ends
    uint256 public constant TICK_SPACING = 100 << FixedPoint96.RESOLUTION;
    uint256 public constant FLOOR_PRICE = 1000 << FixedPoint96.RESOLUTION;
    uint128 public constant TOTAL_SUPPLY = 1000e18;
    uint256 public constant TOTAL_SUPPLY_Q96 = TOTAL_SUPPLY * FixedPoint96.Q96;

    // Common test values
    uint24 public constant STANDARD_MPS_1_PERCENT = 100_000; // 100e3 - represents 1% of MPS

    uint256 public constant MAX_ALLOWABLE_DUST_WEI = 1e18; // Or 1 unit of token assuming 18 decimals

    // Test accounts
    address public alice;
    address public bob;
    address public tokensRecipient;
    address public fundsRecipient;

    AuctionParameters public params;
    uint128 public totalSupply;
    FuzzDeploymentParams public $deploymentParams;
    bytes public auctionStepsData;

    uint128 public $bidAmount;
    uint256 public $maxPrice;

    // ============================================
    // Fuzz Parameter Validation Helpers
    // ============================================

    /// @notice Get a random divisor of ConstantsLib.MPS (10,000,000) that fits in uint8
    /// @return A random valid divisor for numberOfSteps
    function _getRandomDivisorOfMPS() private returns (uint8) {
        // TODO(md): improve
        // All divisors of 10,000,000 that fit in uint8 (1-255)
        uint8[] memory validDivisors = new uint8[](20);
        validDivisors[0] = 1;
        validDivisors[1] = 2;
        validDivisors[2] = 4;
        validDivisors[3] = 5;
        validDivisors[4] = 8;
        validDivisors[5] = 10;
        validDivisors[6] = 16;
        validDivisors[7] = 20;
        validDivisors[8] = 25;
        validDivisors[9] = 32;
        validDivisors[10] = 40;
        validDivisors[11] = 50;
        validDivisors[12] = 64;
        validDivisors[13] = 80;
        validDivisors[14] = 100;
        validDivisors[15] = 125;
        validDivisors[16] = 128;
        validDivisors[17] = 160;
        validDivisors[18] = 200;
        validDivisors[19] = 250;

        // Randomly select one of the valid divisors
        uint256 randomIndex = _bound(uint256(vm.randomUint()), 0, validDivisors.length - 1);
        return validDivisors[randomIndex];
    }

    function helper__validInvariantDeploymentParams() public returns (FuzzDeploymentParams memory) {
        FuzzDeploymentParams memory deploymentParams;

        _setHardcodedParams(deploymentParams);

        // Generate the random parameteres here
        deploymentParams.totalSupply = uint128(_bound(uint256(vm.randomUint()), 1, type(uint128).max));

        // Calculate the number of steps - ensure it's a divisor of ConstantsLib.MPS
        deploymentParams.numberOfSteps = _getRandomDivisorOfMPS();

        // TODO: these values are wrong - tick spacing too large
        deploymentParams.auctionParams.floorPrice =
            uint128(_bound(uint256(vm.randomUint()), ConstantsLib.MIN_TICK_SPACING, type(uint64).max));
        deploymentParams.auctionParams.tickSpacing = uint256(
            _bound(uint256(vm.randomUint()), ConstantsLib.MIN_TICK_SPACING, deploymentParams.auctionParams.floorPrice)
        );
        _boundPriceParams(deploymentParams);

        // Set up the block numbers
        deploymentParams.auctionParams.startBlock = uint64(_bound(uint256(vm.randomUint()), 1, type(uint64).max));
        _boundBlockNumbers(deploymentParams);

        // TODO(md): fix and have variation in the step sizes
        deploymentParams.auctionParams.auctionStepsData = _generateAuctionSteps(deploymentParams.numberOfSteps);

        $deploymentParams = deploymentParams;
        return deploymentParams;
    }

    function helper__validFuzzDeploymentParams(FuzzDeploymentParams memory _deploymentParams)
        public
        returns (AuctionParameters memory)
    {
        _setHardcodedParams(_deploymentParams);
        vm.assume(_deploymentParams.totalSupply > 0);

        _boundBlockNumbers(_deploymentParams);
        _boundPriceParams(_deploymentParams);

        vm.assume(_deploymentParams.numberOfSteps > 0);
        vm.assume(ConstantsLib.MPS % _deploymentParams.numberOfSteps == 0); // such that it is divisible

        // TODO(md): fix and have variation in the step sizes
        _deploymentParams.auctionParams.auctionStepsData = _generateAuctionSteps(_deploymentParams.numberOfSteps);

        $deploymentParams = _deploymentParams;
        totalSupply = _deploymentParams.totalSupply;
        return _deploymentParams.auctionParams;
    }

    function _setHardcodedParams(FuzzDeploymentParams memory _deploymentParams) private view {
        _deploymentParams.auctionParams.currency = ETH_SENTINEL;
        _deploymentParams.auctionParams.tokensRecipient = tokensRecipient;
        _deploymentParams.auctionParams.fundsRecipient = fundsRecipient;
        _deploymentParams.auctionParams.validationHook = address(0);
    }

    function _boundBlockNumbers(FuzzDeploymentParams memory _deploymentParams) private view {
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
    }

    function _boundPriceParams(FuzzDeploymentParams memory _deploymentParams) private pure {
        // Re-implementation of the max bid price calculation in auction constructor
        uint256 maxBidPrice =
            FixedPointMathLib.min(type(uint256).max / _deploymentParams.totalSupply, ConstantsLib.MAX_BID_PRICE);
        // Bound tick spacing and floor price to reasonable values
        _deploymentParams.auctionParams.floorPrice = _bound(
            _deploymentParams.auctionParams.floorPrice,
            ConstantsLib.MIN_TICK_SPACING,
            maxBidPrice - ConstantsLib.MIN_TICK_SPACING
        );

        // Bound tick spacing to be less than or equal to floor price
        _deploymentParams.auctionParams.tickSpacing = _bound(
            _deploymentParams.auctionParams.tickSpacing,
            ConstantsLib.MIN_TICK_SPACING,
            maxBidPrice - _deploymentParams.auctionParams.floorPrice
        );
        // Round down floor price to the closest multiple of tick spacing
        _deploymentParams.auctionParams.floorPrice = helper__roundPriceDownToTickSpacing(
            _deploymentParams.auctionParams.floorPrice, _deploymentParams.auctionParams.tickSpacing
        );

        // Ensure floor price is non-zero
        vm.assume(_deploymentParams.auctionParams.floorPrice != 0);
    }

    function _generateAuctionSteps(uint256 numberOfSteps) private pure returns (bytes memory) {
        uint256 mpsPerStep = ConstantsLib.MPS / numberOfSteps;
        bytes memory stepsData = new bytes(0);
        for (uint8 i = 0; i < numberOfSteps; i++) {
            stepsData = AuctionStepsBuilder.addStep(stepsData, uint24(mpsPerStep), uint40(1));
        }
        return stepsData;
    }

    // ============================================
    // Block Management Helpers
    // ============================================

    function helper__goToAuctionStartBlock() public {
        vm.roll(auction.startBlock());
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

    // ============================================
    // Price Calculation Helpers
    // ============================================

    function helper__roundPriceDownToTickSpacing(uint256 _price, uint256 _tickSpacing) internal pure returns (uint256) {
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
        returns (uint256 maxPrice)
    {
        uint256 tickSpacing = params.tickSpacing;
        uint256 floorPrice = params.floorPrice;

        if (_tickNumber == 0) return floorPrice;

        maxPrice = _bound(floorPrice + (_tickNumber * tickSpacing), floorPrice, type(uint256).max);
    }

    function helper__assumeValidMaxPrice(
        uint256 _floorPrice,
        uint256 _maxPrice,
        uint128 _totalSupply,
        uint256 _tickSpacing
    ) internal pure returns (uint256) {
        vm.assume(_totalSupply != 0 && _tickSpacing != 0 && _floorPrice != 0 && _maxPrice != 0);
        uint256 maxBidPrice = FixedPointMathLib.min(type(uint256).max / _totalSupply, ConstantsLib.MAX_BID_PRICE);
        _maxPrice = _bound(_maxPrice, _floorPrice, maxBidPrice - _tickSpacing);
        _maxPrice = helper__roundPriceDownToTickSpacing(_maxPrice, _tickSpacing);
        vm.assume(_maxPrice > _floorPrice && _maxPrice <= maxBidPrice);
        return _maxPrice;
    }

    // ============================================
    // Bid Submission Helpers
    // ============================================

    /// @dev Submit a bid for a given tick number, amount, and owner
    /// @dev if the bid was not successfully placed - i.e. it would not have succeeded at clearing - bidPlaced is false and bidId is 0
    function helper__trySubmitBid(
        uint256,
        /* _i */
        FuzzBid memory _bid,
        address _owner
    )
        internal
        returns (bool bidPlaced, uint256 bidId)
    {
        Checkpoint memory latestCheckpoint = auction.checkpoint();
        uint256 clearingPrice = latestCheckpoint.clearingPrice;

        // Get the correct bid prices for the bid
        uint256 maxPrice = helper__maxPriceMultipleOfTickSpacingAboveFloorPrice(_bid.tickNumber);
        // if the bid if not above the clearing price, don't submit the bid
        if (maxPrice <= clearingPrice) return (false, 0);
        // Assume the max price is valid
        maxPrice =
            helper__assumeValidMaxPrice(auction.floorPrice(), maxPrice, auction.totalSupply(), auction.tickSpacing());
        uint128 ethInputAmount = inputAmountForTokens(_bid.bidAmount, maxPrice);

        vm.assume(
            auction.sumCurrencyDemandAboveClearingQ96()
                < ConstantsLib.X7_UPPER_BOUND - (ethInputAmount * FixedPoint96.Q96 * ConstantsLib.MPS)
                    / (ConstantsLib.MPS - latestCheckpoint.cumulativeMps)
        );

        // Get the correct last tick price for the bid
        uint256 lowerTickNumber = tickBitmap.findPrev(_bid.tickNumber);
        uint256 lastTickPrice = helper__maxPriceMultipleOfTickSpacingAboveFloorPrice(lowerTickNumber);
        if (lastTickPrice > maxPrice) {
            lastTickPrice = auction.floorPrice();
        }

        try auction.submitBid{value: ethInputAmount}(
            maxPrice, ethInputAmount, _owner, lastTickPrice, bytes('')
        ) returns (
            uint256 _bidId
        ) {
            bidId = _bidId;
        } catch (bytes memory revertData) {
            if (_shouldSkipBidError(revertData, maxPrice)) {
                return (false, 0);
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

    /// @dev Check if a bid error should be skipped in fuzz testing
    function _shouldSkipBidError(bytes memory revertData, uint256 maxPrice) private returns (bool) {
        bytes4 errorSelector = bytes4(revertData);

        // Ok if the bid price is invalid IF it just moved this block
        if (
            errorSelector
                == bytes4(abi.encodeWithSelector(IContinuousClearingAuction.BidMustBeAboveClearingPrice.selector))
        ) {
            Checkpoint memory checkpoint = auction.checkpoint();
            // the bid price is invalid as it is less than or equal to the clearing price
            // skip the test by returning false and 0
            if (maxPrice <= checkpoint.clearingPrice) return true;
            revert('Uncaught BidMustBeAboveClearingPrice');
        }

        return false;
    }

    // ============================================
    // Test Setup Functions & Modifiers
    // ============================================

    /// @dev All bids provided to bid fuzz must have some value and a positive tick number
    modifier setUpBidsFuzz(FuzzBid[] memory _bids) {
        for (uint256 i = 0; i < _bids.length; i++) {
            // Note(md): errors when bumped to uint128
            _bids[i].bidAmount = uint64(_bound(_bids[i].bidAmount, 1, type(uint64).max));
            _bids[i].tickNumber = uint8(_bound(_bids[i].tickNumber, 1, type(uint8).max));
        }
        _;
    }

    modifier requireAuctionNotSetup() {
        require(address(auction) == address(0), 'Auction already setup');
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

    modifier setUpAuctionFuzz(FuzzDeploymentParams memory _deploymentParams) {
        setUpAuction(_deploymentParams);
        _;
    }

    // Fuzzing variant of setUpAuction
    function setUpAuction(FuzzDeploymentParams memory _deploymentParams) public requireAuctionNotSetup {
        setUpTokens();

        alice = makeAddr('alice');
        bob = makeAddr('bob');
        tokensRecipient = makeAddr('tokensRecipient');
        fundsRecipient = makeAddr('fundsRecipient');

        params = helper__validFuzzDeploymentParams(_deploymentParams);

        // Expect the floor price tick to be initialized
        vm.expectEmit(true, true, true, true);
        emit ITickStorage.TickInitialized(_deploymentParams.auctionParams.floorPrice);
        auction = new ContinuousClearingAuction(address(token), _deploymentParams.totalSupply, params);

        token.mint(address(auction), _deploymentParams.totalSupply);
        auction.onTokensReceived();
    }

    // Non-fuzzing variant of setUpAuction
    function setUpAuction() public requireAuctionNotSetup {
        setUpTokens();

        alice = makeAddr('alice');
        bob = makeAddr('bob');
        tokensRecipient = makeAddr('tokensRecipient');
        fundsRecipient = makeAddr('fundsRecipient');

        auctionStepsData =
            AuctionStepsBuilder.init().addStep(STANDARD_MPS_1_PERCENT, 50).addStep(STANDARD_MPS_1_PERCENT, 50);
        params = AuctionParamsBuilder.init().withCurrency(ETH_SENTINEL).withFloorPrice(FLOOR_PRICE)
            .withTickSpacing(TICK_SPACING).withValidationHook(address(0)).withTokensRecipient(tokensRecipient)
            .withFundsRecipient(fundsRecipient).withStartBlock(block.number)
            .withEndBlock(block.number + AUCTION_DURATION)
            .withClaimBlock(block.number + AUCTION_DURATION + CLAIM_BLOCK_OFFSET).withAuctionStepsData(auctionStepsData);

        // Expect the floor price tick to be initialized
        vm.expectEmit(true, true, true, true);
        emit ITickStorage.TickInitialized(tickNumberToPriceX96(1));
        auction = new ContinuousClearingAuction(address(token), TOTAL_SUPPLY, params);

        token.mint(address(auction), TOTAL_SUPPLY);
        // Expect the tokens to be received
        auction.onTokensReceived();
    }

    // ============================================
    // Special Auction Configurations
    // ============================================

    function helper__deployAuctionWithFailingToken() internal returns (ContinuousClearingAuction) {
        MockToken failingToken = new MockToken();

        bytes memory failingAuctionStepsData = AuctionStepsBuilder.init().addStep(STANDARD_MPS_1_PERCENT, 100);
        AuctionParameters memory failingParams = AuctionParamsBuilder.init().withCurrency(ETH_SENTINEL)
            .withFloorPrice(FLOOR_PRICE).withTickSpacing(TICK_SPACING).withValidationHook(address(0))
            .withTokensRecipient(tokensRecipient).withFundsRecipient(fundsRecipient).withStartBlock(block.number)
            .withEndBlock(block.number + AUCTION_DURATION)
            .withClaimBlock(block.number + AUCTION_DURATION + CLAIM_BLOCK_OFFSET)
            .withAuctionStepsData(failingAuctionStepsData);

        ContinuousClearingAuction failingAuction =
            new ContinuousClearingAuction(address(failingToken), TOTAL_SUPPLY, failingParams);
        failingToken.mint(address(failingAuction), TOTAL_SUPPLY);
        failingAuction.onTokensReceived();

        return failingAuction;
    }

    // ============================================
    // Bid & Price Validation Modifiers
    // ============================================

    /// @dev Uses default values for floor price and tick spacing
    modifier givenValidMaxPrice(uint256 _maxPrice, uint128 _totalSupply) {
        $maxPrice = helper__assumeValidMaxPrice(FLOOR_PRICE, _maxPrice, _totalSupply, TICK_SPACING);
        _;
    }

    modifier givenValidMaxPriceWithParams(
        uint256 _maxPrice,
        uint128 _totalSupply,
        uint256 _floorPrice,
        uint256 _tickSpacing
    ) {
        $maxPrice = helper__assumeValidMaxPrice(_floorPrice, _maxPrice, _totalSupply, _tickSpacing);
        _;
    }

    modifier givenValidBidAmount(uint128 _bidAmount) {
        $bidAmount = SafeCastLib.toUint128(_bound(_bidAmount, 1, type(uint128).max));
        _;
    }

    modifier givenGraduatedAuction() {
        // The max currency that can be raised from this bid is totalSupply * maxPrice
        uint256 maxCurrencyRaised = uint256($deploymentParams.totalSupply).fullMulDiv($maxPrice, FixedPoint96.Q96);
        // Require the graduation threshold to be less than the max currency that can be raised
        vm.assume(params.requiredCurrencyRaised <= maxCurrencyRaised);
        // Assume that the bid surpasses the graduation threshold
        vm.assume($bidAmount >= params.requiredCurrencyRaised);
        _;
    }

    modifier givenNotGraduatedAuction() {
        vm.assume($bidAmount < params.requiredCurrencyRaised);
        _;
    }

    modifier checkAuctionIsSolvent() {
        _;
        require(block.number >= auction.endBlock(), 'checkAuctionIsSolvent: Auction is not over');
        auction.checkpoint();
        if (auction.isGraduated()) {
            emit log_string('==================== INFO ====================');
            emit log_named_decimal_uint('auction.totalSupply()', auction.totalSupply(), 18);
            emit log_named_decimal_uint('auction.totalCleared()', auction.totalCleared(), 18);

            assertLe(auction.totalCleared(), auction.totalSupply(), 'total cleared must be <= total supply');

            auction.sweepCurrency();
            auction.sweepUnsoldTokens();
            // Validate that the tokens and currency dust left in the auction is within a reasonable amount
            assertApproxEqAbs(
                token.balanceOf(address(auction)),
                0,
                MAX_ALLOWABLE_DUST_WEI,
                'Auction should have less than MAX_ALLOWABLE_DUST_WEI tokens left'
            );
            assertApproxEqAbs(
                address(auction).balance,
                0,
                MAX_ALLOWABLE_DUST_WEI,
                'Auction should have less than MAX_ALLOWABLE_DUST_WEI wei left of currency'
            );

            emit log_named_decimal_uint(
                'after sweeping token.balanceOf(address(auction))', token.balanceOf(address(auction)), 18
            );
            emit log_named_decimal_uint('after sweeping currency balance', address(auction).balance, 18);
        } else {
            auction.sweepUnsoldTokens();
            // Assert that all tokens were swept
            assertEq(token.balanceOf(auction.tokensRecipient()), auction.totalSupply());
            // Expect to revert when sweeping currency
            vm.expectRevert(ITokenCurrencyStorage.NotGraduated.selector);
            auction.sweepCurrency();
        }
    }

    modifier checkAuctionIsGraduated() {
        _;
        require(block.number >= auction.endBlock(), 'checkAuctionIsGraduated: Auction is not over');
        auction.checkpoint();
        assertTrue(auction.isGraduated());
    }

    modifier checkAuctionIsNotGraduated() {
        _;
        require(block.number >= auction.endBlock(), 'checkAuctionIsNotGraduated: Auction is not over');
        auction.checkpoint();
        assertFalse(auction.isGraduated());
    }

    function helper__submitBid(ContinuousClearingAuction _auction, address _owner, uint128 _amount, uint256 _maxPrice)
        internal
        returns (uint256)
    {
        return _auction.submitBid{value: _amount}(_maxPrice, _amount, _owner, params.floorPrice, bytes(''));
    }

    /// @notice Helper to submit N number of bids at the same amount and max price
    function helper__submitNBids(
        ContinuousClearingAuction _auction,
        address _owner,
        uint128 _amount,
        uint128 _numberOfBids,
        uint256 _maxPrice
    ) internal returns (uint256[] memory) {
        // Split the amount between the bids
        uint128 amountPerBid = _amount / _numberOfBids;

        uint256[] memory bids = new uint256[](_numberOfBids);
        for (uint256 i = 0; i < _numberOfBids; i++) {
            bids[i] = helper__submitBid(_auction, _owner, amountPerBid, _maxPrice);
        }
        return bids;
    }

    /// @dev Helper function to convert a tick number to a priceX96
    function tickNumberToPriceX96(uint256 tickNumber) internal pure returns (uint256) {
        return FLOOR_PRICE + (tickNumber - 1) * TICK_SPACING;
    }

    /// Return the inputAmount required to purchase at least the given number of tokens at the given maxPrice
    function inputAmountForTokens(uint128 tokens, uint256 maxPrice) internal pure returns (uint128) {
        uint256 temp = tokens.fullMulDivUp(maxPrice, FixedPoint96.Q96);
        temp = _bound(temp, 1, type(uint128).max);
        return SafeCastLib.toUint128(temp);
    }

    // ============================================
    // Logging utilities
    // ============================================
    function logFuzzDeploymentParams(FuzzDeploymentParams memory _deploymentParams) public pure {
        console.log('---------FuzzDeploymentParams--------');
        console.log('totalSupply', _deploymentParams.totalSupply);
        console.log('numberOfSteps', _deploymentParams.numberOfSteps);
        logAuctionParams(_deploymentParams.auctionParams);
    }

    function logAuctionParams(AuctionParameters memory _params) public pure {
        console.log('---------AuctionParams--------');
        console.log('currency', _params.currency);
        console.log('tokensRecipient', _params.tokensRecipient);
        console.log('fundsRecipient', _params.fundsRecipient);
        console.log('startBlock', _params.startBlock);
        console.log('endBlock', _params.endBlock);
        console.log('claimBlock', _params.claimBlock);
        console.log('tickSpacing', _params.tickSpacing);
        console.log('validationHook', _params.validationHook);
        console.log('floorPrice', _params.floorPrice);
        console.log('auctionStepsData');
        console.logBytes(_params.auctionStepsData);
    }
}
