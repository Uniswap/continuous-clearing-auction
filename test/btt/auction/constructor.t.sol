// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {AuctionFuzzConstructorParams, BttBase} from '../BttBase.sol';
import {FixedPointMathLib} from 'solady/utils/FixedPointMathLib.sol';
import {Auction} from 'src/Auction.sol';
import {IAuction} from 'src/interfaces/IAuction.sol';
import {ConstantsLib} from 'src/libraries/ConstantsLib.sol';
import {FixedPoint96} from 'src/libraries/FixedPoint96.sol';
import {LiquidityAmounts} from 'v4-periphery/src/libraries/LiquidityAmounts.sol';

contract AuctionConstructorTest is BttBase {
    function test_WhenClaimBlockLTEndBlock(AuctionFuzzConstructorParams memory _params)
        external
        setupAuctionConstructorParams(_params)
    {
        // it reverts with {ClaimBlockIsBeforeEndBlock}

        // Set the claim block to be less than the end block
        _params.parameters.claimBlock = uint64(bound(_params.parameters.claimBlock, 0, _params.parameters.endBlock - 1));

        vm.expectRevert(IAuction.ClaimBlockIsBeforeEndBlock.selector);
        new Auction(_params.token, _params.totalSupply, _params.parameters);
    }

    /// @dev Legacy test but will keep
    function test_WhenTypeUint256MaxDivTotalSupplyLTUniV4MaxTick(AuctionFuzzConstructorParams memory _params)
        external
        setupAuctionConstructorParams(_params)
    {
        // it sets bid max price to be ConstantsLib.MAX_BID_PRICE / totalSupply

        _params.totalSupply = uint128(_bound(_params.totalSupply, 1, ConstantsLib.MAX_TOTAL_SUPPLY));
        uint256 expectedBidMaxPrice = ConstantsLib.MAX_BID_PRICE / _params.totalSupply;

        Auction auction = new Auction(_params.token, _params.totalSupply, _params.parameters);

        assertEq(auction.MAX_BID_PRICE(), expectedBidMaxPrice);
        // 1 << 224 is the maximum price supported by Uniswap v4
        assertLt(auction.MAX_BID_PRICE(), 1 << 224);
    }

    function test_WhenTotalSupplyIsLTEMAX_TOTAL_SUPPLYBidMaxPriceIsWithinV4LiquidityBounds(
        AuctionFuzzConstructorParams memory _params,
        uint256 clearingPrice,
        bool currencyIsToken0
    ) external setupAuctionConstructorParams(_params) {
        // it sets bid max price to be ConstantsLib.MAX_BID_PRICE / totalSupply
        // and the final liquidity is within the bounds of Uniswap v4

        _params.totalSupply = uint128(_bound(_params.totalSupply, 1, ConstantsLib.MAX_TOTAL_SUPPLY));
        uint256 maxBidPrice = ConstantsLib.MAX_BID_PRICE / _params.totalSupply;
        clearingPrice = _bound(clearingPrice, 1, maxBidPrice);
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

    function test_WhenClaimBlockGEEndBlock(AuctionFuzzConstructorParams memory _params)
        external
        setupAuctionConstructorParams(_params)
    {
        // it writes CLAIM_BLOCK
        // it writes VALIDATION_HOOK
        // it writes BID_MAX_PRICE

        _params.parameters.claimBlock =
            uint64(bound(_params.parameters.claimBlock, _params.parameters.endBlock, type(uint64).max));

        uint256 expectedBidMaxPrice = ConstantsLib.MAX_BID_PRICE / _params.totalSupply;

        Auction auction = new Auction(_params.token, _params.totalSupply, _params.parameters);

        assertEq(auction.claimBlock(), _params.parameters.claimBlock);
        assertEq(address(auction.validationHook()), _params.parameters.validationHook);
        assertEq(auction.MAX_BID_PRICE(), expectedBidMaxPrice);
    }
}
