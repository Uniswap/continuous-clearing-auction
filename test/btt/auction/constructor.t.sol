// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import {AuctionFuzzConstructorParams, BttBase} from '../BttBase.sol';
import {FixedPointMathLib} from 'solady/utils/FixedPointMathLib.sol';
import {ContinuousClearingAuction} from 'src/ContinuousClearingAuction.sol';
import {IContinuousClearingAuction} from 'src/interfaces/IContinuousClearingAuction.sol';
import {ConstantsLib} from 'src/libraries/ConstantsLib.sol';
import {FixedPoint96} from 'src/libraries/FixedPoint96.sol';
import {MaxBidPriceLib} from 'src/libraries/MaxBidPriceLib.sol';
import {LiquidityAmountsUint256} from 'test/utils/LiquidityAmountsUint256.sol';
import {LiquidityAmounts} from 'v4-periphery/src/libraries/LiquidityAmounts.sol';

contract ConstructorTest is BttBase {
    /// @dev min sqrt price copied from TickMath.MIN_SQRT_PRICE
    uint160 MIN_SQRT_PRICE = 4_295_128_739;
    /// @dev max sqrt price copied from TickMath.MAX_SQRT_PRICE
    uint160 MAX_SQRT_PRICE = 1_461_446_703_485_210_103_287_273_052_203_988_822_378_723_970_342;

    /**
     * Uniswap v4 max liqudity per tick is 2^128 - 1 / number of ticks + 1
     * Given the lowest supported tick spacing of 1, we have 2 * 887272 = 1774544 ticks
     * Thus the bound on max liquidity per tick is (2^128 - 1) / (1774544 + 1) = 191757530477355300863043035987968
     */
    uint256 MAX_LIQUIDITY_BOUND = 191_757_530_477_355_300_863_043_035_987_968;

    function test_WhenClaimBlockLTEndBlock(AuctionFuzzConstructorParams memory _params) external {
        // it reverts with {ClaimBlockIsBeforeEndBlock}

        AuctionFuzzConstructorParams memory mParams = validAuctionConstructorInputs(_params);
        mParams.parameters.claimBlock = uint64(bound(mParams.parameters.claimBlock, 0, mParams.parameters.endBlock - 1));

        vm.expectRevert(IContinuousClearingAuction.ClaimBlockIsBeforeEndBlock.selector);
        new ContinuousClearingAuction(mParams.token, mParams.totalSupply, mParams.parameters);
    }

    function test_WhenClaimBlockGEEndBlock(AuctionFuzzConstructorParams memory _params, uint64 _claimBlock)
        external
        setupAuctionConstructorParams(_params)
    {
        // it writes CLAIM_BLOCK
        // it writes VALIDATION_HOOK
        // it writes BID_MAX_PRICE

        AuctionFuzzConstructorParams memory mParams = validAuctionConstructorInputs(_params);
        mParams.parameters.claimBlock = uint64(bound(_claimBlock, mParams.parameters.endBlock, type(uint64).max));
        mParams.totalSupply = uint128(bound(mParams.totalSupply, 1, ConstantsLib.MAX_TOTAL_SUPPLY));

        uint256 computedMaxBidPrice = MaxBidPriceLib.maxBidPrice(mParams.totalSupply);

        ContinuousClearingAuction auction =
            new ContinuousClearingAuction(mParams.token, mParams.totalSupply, mParams.parameters);

        assertEq(auction.MAX_BID_PRICE(), computedMaxBidPrice);
        assertEq(auction.claimBlock(), mParams.parameters.claimBlock);
        assertEq(address(auction.validationHook()), address(mParams.parameters.validationHook));
    }

    modifier whenClaimBlockGEEndBlock() {
        _;
    }

    function test_WhenTotalSupplyIsEQMaxTotalSupply(AuctionFuzzConstructorParams memory _params) external {
        // it sets bid max price to be MaxBidPriceLib.maxBidPrice(MAX_TOTAL_SUPPLY)

        AuctionFuzzConstructorParams memory mParams = validAuctionConstructorInputs(_params);
        mParams.totalSupply = ConstantsLib.MAX_TOTAL_SUPPLY;
        uint256 computedMaxBidPrice = MaxBidPriceLib.maxBidPrice(mParams.totalSupply);

        // Just to pass checks
        mParams.parameters.floorPrice = ConstantsLib.MIN_FLOOR_PRICE;
        mParams.parameters.tickSpacing = ConstantsLib.MIN_TICK_SPACING;

        ContinuousClearingAuction auction =
            new ContinuousClearingAuction(mParams.token, mParams.totalSupply, mParams.parameters);
        assertEq(auction.MAX_BID_PRICE(), computedMaxBidPrice);
    }

    function test_WhenTotalSupplyIsEQ1(AuctionFuzzConstructorParams memory _params) external pure {
        // it sets bid max price to be MAX_V4_PRICE

        AuctionFuzzConstructorParams memory mParams = validAuctionConstructorInputs(_params);
        mParams.totalSupply = 1;
        uint256 computedMaxBidPrice = MaxBidPriceLib.maxBidPrice(mParams.totalSupply);

        assertEq(computedMaxBidPrice, MaxBidPriceLib.MAX_V4_PRICE);
    }

    function test_WhenTotalSupplyIsBelowLowerTotalSupplyThreshold(AuctionFuzzConstructorParams memory _params)
        external
    {
        // it sets bid max price to be MaxBidPriceLib.MAX_V4_PRICE

        AuctionFuzzConstructorParams memory mParams = validAuctionConstructorInputs(_params);
        mParams.totalSupply = uint128(bound(mParams.totalSupply, 1, MaxBidPriceLib.LOWER_TOTAL_SUPPLY_THRESHOLD));

        ContinuousClearingAuction auction =
            new ContinuousClearingAuction(mParams.token, mParams.totalSupply, mParams.parameters);
        assertEq(auction.MAX_BID_PRICE(), MaxBidPriceLib.MAX_V4_PRICE);
    }

    function test_WhenTotalSupplyIsAtLowerTotalSupplyThreshold(AuctionFuzzConstructorParams memory _params) external {
        // it sets bid max price to be MaxBidPriceLib.MAX_V4_PRICE

        AuctionFuzzConstructorParams memory mParams = validAuctionConstructorInputs(_params);
        mParams.totalSupply = uint128(MaxBidPriceLib.LOWER_TOTAL_SUPPLY_THRESHOLD);

        ContinuousClearingAuction auction =
            new ContinuousClearingAuction(mParams.token, mParams.totalSupply, mParams.parameters);
        assertEq(auction.MAX_BID_PRICE(), MaxBidPriceLib.MAX_V4_PRICE);
    }

    function test_WhenTotalSupplyIsAtOrAboveLowerTotalSupplyThreshold(AuctionFuzzConstructorParams memory _params)
        external
    {
        // it sets bid max price to be MaxBidPriceLib.maxBidPrice(totalSupply)

        AuctionFuzzConstructorParams memory mParams = validAuctionConstructorInputs(_params);
        mParams.totalSupply = uint128(
            bound(mParams.totalSupply, MaxBidPriceLib.LOWER_TOTAL_SUPPLY_THRESHOLD, ConstantsLib.MAX_TOTAL_SUPPLY)
        );

        mParams.parameters.floorPrice = ConstantsLib.MIN_FLOOR_PRICE;
        mParams.parameters.tickSpacing = ConstantsLib.MIN_TICK_SPACING;

        ContinuousClearingAuction auction =
            new ContinuousClearingAuction(mParams.token, mParams.totalSupply, mParams.parameters);
        assertEq(auction.MAX_BID_PRICE(), MaxBidPriceLib.maxBidPrice(mParams.totalSupply));
    }

    /// forge-config: default.fuzz.runs = 5000
    function test_WhenTotalSupplyIsLTEMAX_TOTAL_SUPPLYBidMaxPriceIsWithinV4LiquidityBounds(
        AuctionFuzzConstructorParams memory _params,
        uint256 clearingPrice,
        bool currencyIsToken0
    ) external setupAuctionConstructorParams(_params) {
        // it calculates max bid price to be within uni v4 liquidity bounds

        _params.totalSupply = uint128(_bound(_params.totalSupply, 1, ConstantsLib.MAX_TOTAL_SUPPLY));
        uint256 computedMaxBidPrice = MaxBidPriceLib.maxBidPrice(_params.totalSupply);
        // The min possible clearing price is the min floor price
        clearingPrice = _bound(clearingPrice, ConstantsLib.MIN_FLOOR_PRICE + 1, computedMaxBidPrice);
        assertLe(clearingPrice, MaxBidPriceLib.MAX_V4_PRICE, 'clearingPrice is greater than MAX_V4_PRICE');
        assertLe(clearingPrice, type(uint160).max, 'clearingPrice is greater than type(uint160).max');

        // Calculate the currency amount if all of the supply was sold at the clearing price
        uint256 currencyAmount = FixedPointMathLib.fullMulDiv(_params.totalSupply, clearingPrice, FixedPoint96.Q96);
        assertLe(int256(currencyAmount), int256(type(int128).max), 'currencyAmount is greater than type(int128).max');

        // If currency is currency0, we need to invert the price (price = currency1/currency0)
        uint256 temp;
        if (currencyIsToken0) {
            // Inverts the Q96 price: (2^192 * 2^96 / priceQ96) = (2^96 / actualPrice), maintaining Q96 format
            clearingPrice = FixedPointMathLib.fullMulDiv(1 << 192, 1 << 96, clearingPrice);
            temp = FixedPointMathLib.sqrt(clearingPrice);
        } else {
            temp = FixedPointMathLib.sqrt(clearingPrice << 96);
        }
        if (temp > type(uint160).max) {
            revert('sqrtPriceX96 is greater than type(uint160).max');
        }
        uint160 sqrtPriceX96 = uint160(temp);

        // Ensure the sqrt price is within the valid range
        assertGt(sqrtPriceX96, MIN_SQRT_PRICE, 'sqrtPriceX96 is less than MIN_SQRT_PRICE');
        assertLt(sqrtPriceX96, MAX_SQRT_PRICE, 'sqrtPriceX96 is greater than MAX_SQRT_PRICE');

        emit log_named_uint('sqrtPriceX96', sqrtPriceX96);
        emit log_named_uint('currencyAmount', currencyAmount);
        emit log_named_uint('_params.totalSupply', _params.totalSupply);

        // Since sqrtPriceX96 is guaranteed to be between min sqrt price and max sqrt price
        uint256 currencyL;
        uint256 tokenL;
        if (currencyIsToken0) {
            currencyL =
                LiquidityAmountsUint256.getLiquidityForAmount0_Uint256(sqrtPriceX96, MAX_SQRT_PRICE, currencyAmount);
            tokenL = LiquidityAmountsUint256.getLiquidityForAmount1_Uint256(
                MIN_SQRT_PRICE, sqrtPriceX96, _params.totalSupply
            );
        } else {
            currencyL =
                LiquidityAmountsUint256.getLiquidityForAmount1_Uint256(MIN_SQRT_PRICE, sqrtPriceX96, currencyAmount);
            tokenL = LiquidityAmountsUint256.getLiquidityForAmount0_Uint256(
                sqrtPriceX96, MAX_SQRT_PRICE, _params.totalSupply
            );
        }

        assertLt(currencyL, MAX_LIQUIDITY_BOUND, 'currencyLiquidity is greater than MAX_LIQUIDITY_BOUND');
        assertLt(tokenL, MAX_LIQUIDITY_BOUND, 'tokenLiquidity is greater than MAX_LIQUIDITY_BOUND');

        // Find the maximum liquidity that can be created with this price range
        // Should not revert and should be under MAX_LIQUIDITY_BOUND
        uint128 liquidity = LiquidityAmounts.getLiquidityForAmounts(
            sqrtPriceX96,
            4_295_128_739, // Minimum sqrt price
            1_461_446_703_485_210_103_287_273_052_203_988_822_378_723_970_342, // maximum sqrt price
            currencyIsToken0 ? currencyAmount : _params.totalSupply,
            currencyIsToken0 ? _params.totalSupply : currencyAmount
        );
        assertLt(liquidity, MAX_LIQUIDITY_BOUND, 'liquidity is greater than MAX_LIQUIDITY_BOUND');
        // And since we are doing a full range position, we take the minimum of the two calculated liquidity values
        assertEq(liquidity, FixedPointMathLib.min(currencyL, tokenL));
    }

    modifier whenTotalSupplyLTEMAX_TOTAL_SUPPLY() {
        _;
    }

    function test_WhenFloorPricePlusTickSpacingGTMaxBidPrice(AuctionFuzzConstructorParams memory _params)
        external
        whenTotalSupplyLTEMAX_TOTAL_SUPPLY
    {
        // it reverts with {FloorPriceAndTickSpacingGreaterThanMaxBidPrice}

        AuctionFuzzConstructorParams memory mParams = validAuctionConstructorInputs(_params);
        mParams.totalSupply = uint128(_bound(mParams.totalSupply, 1, ConstantsLib.MAX_TOTAL_SUPPLY));
        uint256 computedMaxBidPrice = MaxBidPriceLib.maxBidPrice(mParams.totalSupply);

        // Set the floor price to be the maximum possible floor price
        mParams.parameters.floorPrice = computedMaxBidPrice;
        // Set tick spacing to be any mod higher than MIN_TICK_SPACING
        mParams.parameters.tickSpacing = ConstantsLib.MIN_TICK_SPACING;
        vm.assume(mParams.parameters.floorPrice % mParams.parameters.tickSpacing == 0);

        vm.expectRevert(
            abi.encodeWithSelector(
                IContinuousClearingAuction.FloorPriceAndTickSpacingGreaterThanMaxBidPrice.selector,
                mParams.parameters.floorPrice + mParams.parameters.tickSpacing,
                computedMaxBidPrice
            )
        );
        new ContinuousClearingAuction(mParams.token, mParams.totalSupply, mParams.parameters);
    }

    function test_WhenFloorPricePlusTickSpacingLTMaxBidPrice(AuctionFuzzConstructorParams memory _params)
        external
        whenTotalSupplyLTEMAX_TOTAL_SUPPLY
    {
        // it writes BID_MAX_PRICE

        AuctionFuzzConstructorParams memory mParams = validAuctionConstructorInputs(_params);
        mParams.totalSupply = uint128(_bound(mParams.totalSupply, 1, ConstantsLib.MAX_TOTAL_SUPPLY));
        uint256 computedMaxBidPrice = MaxBidPriceLib.maxBidPrice(mParams.totalSupply);

        // Set the floor price to be the maximum possible floor price
        mParams.parameters.floorPrice = uint256(
            _bound(
                mParams.parameters.floorPrice,
                ConstantsLib.MIN_TICK_SPACING,
                computedMaxBidPrice - ConstantsLib.MIN_TICK_SPACING
            )
        );
        // Set tick spacing to be any mod higher than MIN_TICK_SPACING
        mParams.parameters.tickSpacing = _bound(
            mParams.parameters.tickSpacing,
            ConstantsLib.MIN_TICK_SPACING,
            computedMaxBidPrice - mParams.parameters.floorPrice
        );
        vm.assume(mParams.parameters.floorPrice % mParams.parameters.tickSpacing == 0);

        ContinuousClearingAuction auction =
            new ContinuousClearingAuction(mParams.token, mParams.totalSupply, mParams.parameters);
        assertEq(auction.MAX_BID_PRICE(), computedMaxBidPrice);
        assertEq(auction.floorPrice(), mParams.parameters.floorPrice);
        assertEq(auction.tickSpacing(), mParams.parameters.tickSpacing);
    }
}
