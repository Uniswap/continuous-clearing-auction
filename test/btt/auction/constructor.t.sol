// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import {AuctionFuzzConstructorParams, BttBase} from '../BttBase.sol';
import {ContinuousClearingAuction} from 'src/ContinuousClearingAuction.sol';
import {IContinuousClearingAuction} from 'src/interfaces/IContinuousClearingAuction.sol';
import {ConstantsLib} from 'src/libraries/ConstantsLib.sol';

contract ConstructorTest is BttBase {
    function test_WhenClaimBlockLTEndBlock(AuctionFuzzConstructorParams memory _params) external {
        // it reverts with {ClaimBlockIsBeforeEndBlock}

        AuctionFuzzConstructorParams memory mParams = validAuctionConstructorInputs(_params);
        mParams.parameters.claimBlock = uint64(bound(mParams.parameters.claimBlock, 0, mParams.parameters.endBlock - 1));

        vm.expectRevert(IContinuousClearingAuction.ClaimBlockIsBeforeEndBlock.selector);
        new ContinuousClearingAuction(mParams.token, mParams.totalSupply, mParams.parameters);
    }

    modifier whenClaimBlockGEEndBlock() {
        _;
    }

    function test_WhenUint256MaxDivTotalSupplyGEUniV4MaxTick(
        AuctionFuzzConstructorParams memory _params,
        uint64 _claimBlock,
        uint128 _totalSupply
    ) external whenClaimBlockGEEndBlock {
        // it writes CLAIM_BLOCK
        // it writes VALIDATION_HOOK
        // it writes BID_MAX_PRICE as uni v4 max tick

        AuctionFuzzConstructorParams memory mParams = validAuctionConstructorInputs(_params);
        mParams.parameters.claimBlock = uint64(bound(_claimBlock, mParams.parameters.endBlock, type(uint64).max));
        mParams.totalSupply = uint128(bound(_totalSupply, 1, type(uint256).max / ConstantsLib.MAX_BID_PRICE));

        ContinuousClearingAuction auction =
            new ContinuousClearingAuction(mParams.token, mParams.totalSupply, mParams.parameters);

        assertEq(auction.MAX_BID_PRICE(), ConstantsLib.MAX_BID_PRICE);
        assertEq(auction.claimBlock(), mParams.parameters.claimBlock);
        assertEq(address(auction.validationHook()), address(mParams.parameters.validationHook));
    }

    modifier whenUint256MaxDivTotalSupplyGEUniV4MaxTick() {
        _;
    }

    function test_WhenUint256MaxDivTotalSupplyLEUniV4MaxTick(
        AuctionFuzzConstructorParams memory _params,
        uint64 _claimBlock,
        uint128 _totalSupply
    ) external whenClaimBlockGEEndBlock {
        // it writes CLAIM_BLOCK
        // it writes VALIDATION_HOOK
        // it writes BID_MAX_PRICE as type(uint256).max / totalSupply

        AuctionFuzzConstructorParams memory mParams = validAuctionConstructorInputs(_params);
        mParams.parameters.claimBlock = uint64(bound(_claimBlock, mParams.parameters.endBlock, type(uint64).max));
        mParams.totalSupply =
            uint128(bound(_totalSupply, type(uint256).max / ConstantsLib.MAX_BID_PRICE + 1, type(uint128).max));
        uint256 computedMaxBidPrice = type(uint256).max / mParams.totalSupply;
        mParams.parameters.floorPrice = bound(
            mParams.parameters.floorPrice,
            ConstantsLib.MIN_TICK_SPACING,
            computedMaxBidPrice - ConstantsLib.MIN_TICK_SPACING
        );
        mParams.parameters.tickSpacing = bound(
            mParams.parameters.tickSpacing,
            ConstantsLib.MIN_TICK_SPACING,
            computedMaxBidPrice - mParams.parameters.floorPrice
        );
        mParams.parameters.floorPrice =
            helper__roundPriceDownToTickSpacing(mParams.parameters.floorPrice, mParams.parameters.tickSpacing);
        vm.assume(mParams.parameters.floorPrice != 0);

        ContinuousClearingAuction auction =
            new ContinuousClearingAuction(mParams.token, mParams.totalSupply, mParams.parameters);

        assertEq(auction.MAX_BID_PRICE(), type(uint256).max / mParams.totalSupply);
        assertEq(auction.claimBlock(), mParams.parameters.claimBlock);
        assertEq(address(auction.validationHook()), address(mParams.parameters.validationHook));
    }

    modifier whenUint256MaxDivTotalSupplyLEUniV4MaxTick() {
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

    function test_WhenFloorPricePlusTickSpacingGTMaxBidPrice_Uint256MaxDivTotalSupplyGEUniV4MaxTick(AuctionFuzzConstructorParams memory _params)
        external
        whenUint256MaxDivTotalSupplyGEUniV4MaxTick
    {
        // it reverts with {TickSpacingTooLarge}

        AuctionFuzzConstructorParams memory mParams = validAuctionConstructorInputs(_params);
        // Set total supply such that the computed max bid price is greater than the ConstantsLib.MAX_BID_PRICE
        mParams.totalSupply = uint128(type(uint256).max / ConstantsLib.MAX_BID_PRICE) - 1;
        // -> so the max bid price is equal to ConstantsLib.MAX_BID_PRICE

        // Set the floor price to be the maximum possible floor price
        mParams.parameters.floorPrice = ConstantsLib.MAX_BID_PRICE;
        // Set tick spacing to be any mod higher than MIN_TICK_SPACING
        mParams.parameters.tickSpacing = _findModulo(mParams.parameters.floorPrice);

        vm.expectRevert(
            abi.encodeWithSelector(
                IContinuousClearingAuction.FloorPriceAndTickSpacingGreaterThanMaxBidPrice.selector,
                mParams.parameters.floorPrice + mParams.parameters.tickSpacing,
                ConstantsLib.MAX_BID_PRICE
            )
        );
        new ContinuousClearingAuction(mParams.token, mParams.totalSupply, mParams.parameters);
    }

    function test_WhenFloorPricePlusTickSpacingGTMaxBidPrice_Uint256MaxDivTotalSupplyLEUniV4MaxTick(AuctionFuzzConstructorParams memory _params)
        external
        whenUint256MaxDivTotalSupplyLEUniV4MaxTick
    {
        // it reverts with {TickSpacingTooLarge}

        AuctionFuzzConstructorParams memory mParams = validAuctionConstructorInputs(_params);
        // Set total supply such that the computed max bid price is less than the ConstantsLib.MAX_BID_PRICE
        mParams.totalSupply = uint128(type(uint256).max / ConstantsLib.MAX_BID_PRICE) + 1;
        uint256 computedMaxBidPrice = type(uint256).max / mParams.totalSupply;
        // -> so the max bid price is equal to ConstantsLib.MAX_BID_PRICE

        // Set the floor price to be the maximum possible floor price
        mParams.parameters.floorPrice = computedMaxBidPrice;
        // Set tick spacing to be any mod higher than MIN_TICK_SPACING
        mParams.parameters.tickSpacing = _findModulo(mParams.parameters.floorPrice);

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
