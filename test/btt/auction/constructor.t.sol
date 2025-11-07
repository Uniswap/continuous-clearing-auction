// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import {AuctionFuzzConstructorParams, BttBase} from '../BttBase.sol';
import {FixedPointMathLib} from 'solady/utils/FixedPointMathLib.sol';
import {ContinuousClearingAuction} from 'src/ContinuousClearingAuction.sol';
import {IContinuousClearingAuction} from 'src/interfaces/IContinuousClearingAuction.sol';
import {ConstantsLib} from 'src/libraries/ConstantsLib.sol';
import {FixedPoint96} from 'src/libraries/FixedPoint96.sol';
import {LiquidityAmounts} from 'v4-periphery/src/libraries/LiquidityAmounts.sol';

contract ConstructorTest is BttBase {
    function test_WhenClaimBlockLTEndBlock(AuctionFuzzConstructorParams memory _params) external {
        // it reverts with {ClaimBlockIsBeforeEndBlock}

        AuctionFuzzConstructorParams memory mParams = validAuctionConstructorInputs(_params);
        mParams.parameters.claimBlock = uint64(bound(mParams.parameters.claimBlock, 0, mParams.parameters.endBlock - 1));

        vm.expectRevert(IContinuousClearingAuction.ClaimBlockIsBeforeEndBlock.selector);
        new ContinuousClearingAuction(mParams.token, mParams.totalSupply, mParams.parameters);
    }

    function test_WhenTotalSupplyIsLTEMAX_TOTAL_SUPPLYBidMaxPriceIsWithinV4LiquidityBounds(
        AuctionFuzzConstructorParams memory _params,
        uint256 clearingPrice,
        bool currencyIsToken0
    ) external setupAuctionConstructorParams(_params) {
        // it sets bid max price to be ConstantsLib.MAX_BID_PRICE / totalSupply
        // and the final liquidity is within the bounds of Uniswap v4

        _params.totalSupply = uint128(_bound(_params.totalSupply, 1, ConstantsLib.MAX_TOTAL_SUPPLY));
        uint256 computedMaxBidPrice = ConstantsLib.MAX_BID_PRICE / _params.totalSupply;
        clearingPrice = _bound(clearingPrice, 1, computedMaxBidPrice);
        uint256 currencyAmount = FixedPointMathLib.fullMulDiv(_params.totalSupply, clearingPrice, FixedPoint96.Q96);

        // Find sqrtPriceX96, have to shift left 96 to get to Q192 form first
        // If currency is currency0, we need to invert the price (price = currency1/currency0)
        if (currencyIsToken0) {
            // Inverts the Q96 price: (2^192 / priceQ96) = (2^96 / actualPrice), maintaining Q96 format
            clearingPrice = (1 << (FixedPoint96.RESOLUTION * 2)) / clearingPrice;
        }
        uint256 temp = FixedPointMathLib.sqrt(clearingPrice << FixedPoint96.RESOLUTION);
        if (temp > type(uint160).max) {
            revert('sqrt price overflow');
        }
        uint160 sqrtPriceX96 = uint160(temp);

        // Find the maximum liquidity that can be created with this price range
        // Should not revert
        LiquidityAmounts.getLiquidityForAmounts(
            sqrtPriceX96,
            4_295_128_739, // Minimum sqrt price
            1_461_446_703_485_210_103_287_273_052_203_988_822_378_723_970_342, // maximum sqrt price
            currencyIsToken0 ? currencyAmount : _params.totalSupply,
            currencyIsToken0 ? _params.totalSupply : currencyAmount
        );
    }

    function test_WhenClaimBlockGEEndBlock(AuctionFuzzConstructorParams memory _params, uint64 _claimBlock)
        external
        setupAuctionConstructorParams(_params)
    {
        // it writes CLAIM_BLOCK
        // it writes VALIDATION_HOOK
        // it writes BID_MAX_PRICE as uni v4 max tick

        AuctionFuzzConstructorParams memory mParams = validAuctionConstructorInputs(_params);
        mParams.parameters.claimBlock = uint64(bound(_claimBlock, mParams.parameters.endBlock, type(uint64).max));
        mParams.totalSupply = uint128(bound(mParams.totalSupply, 1, ConstantsLib.MAX_TOTAL_SUPPLY));

        uint256 computedMaxBidPrice = ConstantsLib.MAX_BID_PRICE / mParams.totalSupply;

        ContinuousClearingAuction auction =
            new ContinuousClearingAuction(mParams.token, mParams.totalSupply, mParams.parameters);

        assertEq(auction.MAX_BID_PRICE(), computedMaxBidPrice);
        assertEq(auction.claimBlock(), mParams.parameters.claimBlock);
        assertEq(address(auction.validationHook()), address(mParams.parameters.validationHook));
    }

    modifier whenClaimBlockGEEndBlock() {
        _;
    }

    // super gas inefficient but whatever
    function _findModulo(uint256 _value) internal pure returns (uint256) {
        if (_value == 0) return 0; // Handle case when _value is 0
        for (uint256 i = ConstantsLib.MIN_TICK_SPACING; i <= _value; i++) {
            if (_value % i == 0) {
                return i;
            }
        }
        revert('No modulo found');
    }

    function test_WhenFloorPricePlusTickSpacingLTMaxBidPrice(AuctionFuzzConstructorParams memory _params) external {
        // it reverts with {FloorPriceAndTickSpacingGreaterThanMaxBidPrice}

        AuctionFuzzConstructorParams memory mParams = validAuctionConstructorInputs(_params);
        // Set total supply such that the computed max bid price is less than the ConstantsLib.MAX_BID_PRICE
        mParams.totalSupply = uint128(_bound(mParams.totalSupply, 1, ConstantsLib.MAX_TOTAL_SUPPLY));
        uint256 computedMaxBidPrice = ConstantsLib.MAX_BID_PRICE / mParams.totalSupply;

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

    function test_WhenFloorPricePlusTickSpacingGTMaxBidPrice(AuctionFuzzConstructorParams memory _params) external {
        // it reverts with {FloorPriceAndTickSpacingGreaterThanMaxBidPrice}

        AuctionFuzzConstructorParams memory mParams = validAuctionConstructorInputs(_params);
        // Set total supply such that the computed max bid price is greater than the ConstantsLib.MAX_BID_PRICE
        mParams.totalSupply = uint128(_bound(mParams.totalSupply, 1, ConstantsLib.MAX_TOTAL_SUPPLY));
        uint256 computedMaxBidPrice = ConstantsLib.MAX_BID_PRICE / mParams.totalSupply;

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
}
