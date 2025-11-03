// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import {AuctionFuzzConstructorParams, BttBase} from '../BttBase.sol';

import {Auction} from 'src/Auction.sol';
import {IAuction} from 'src/interfaces/IAuction.sol';
import {ConstantsLib} from 'src/libraries/ConstantsLib.sol';

contract ConstructorTest is BttBase {
    function test_WhenClaimBlockLTEndBlock(AuctionFuzzConstructorParams memory _params) external {
        // it reverts with {ClaimBlockIsBeforeEndBlock}

        AuctionFuzzConstructorParams memory mParams = validAuctionConstructorInputs(_params);
        mParams.parameters.claimBlock = uint64(bound(mParams.parameters.claimBlock, 0, mParams.parameters.endBlock - 1));

        vm.expectRevert(IAuction.ClaimBlockIsBeforeEndBlock.selector);
        new Auction(mParams.token, mParams.totalSupply, mParams.parameters);
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

        Auction auction = new Auction(mParams.token, mParams.totalSupply, mParams.parameters);

        assertEq(auction.MAX_BID_PRICE(), ConstantsLib.MAX_BID_PRICE);
        assertEq(auction.claimBlock(), mParams.parameters.claimBlock);
        assertEq(address(auction.validationHook()), address(mParams.parameters.validationHook));
    }

    modifier whenUint256MaxDivTotalSupplyGEUniV4MaxTick() {
        _;
    }

    function test_WhenFloorPriceGTConstantsLibMaxBidPrice(
        AuctionFuzzConstructorParams memory _params,
        uint256 _tickSpacing,
        uint256 _floorPrice,
        uint128 _totalSupply
    ) external whenUint256MaxDivTotalSupplyGEUniV4MaxTick {
        // it reverts with {FloorPriceAboveMaxBidPrice}

        AuctionFuzzConstructorParams memory mParams = validAuctionConstructorInputs(_params);
        // Set total supply such that the computed max bid price is greater than the ConstantsLib.MAX_BID_PRICE
        mParams.totalSupply = uint128(bound(_totalSupply, 1, type(uint256).max / ConstantsLib.MAX_BID_PRICE + 1));
        mParams.parameters.floorPrice = bound(_floorPrice, ConstantsLib.MAX_BID_PRICE + 1, type(uint256).max);
        // Easy default to pass the tick boundary check
        mParams.parameters.tickSpacing = mParams.parameters.floorPrice;

        vm.expectRevert(
            abi.encodeWithSelector(
                IAuction.FloorPriceAboveMaxBidPrice.selector, mParams.parameters.floorPrice, ConstantsLib.MAX_BID_PRICE
            )
        );
        new Auction(mParams.token, mParams.totalSupply, mParams.parameters);
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

        Auction auction = new Auction(mParams.token, mParams.totalSupply, mParams.parameters);

        assertEq(auction.MAX_BID_PRICE(), type(uint256).max / mParams.totalSupply);
        assertEq(auction.claimBlock(), mParams.parameters.claimBlock);
        assertEq(address(auction.validationHook()), address(mParams.parameters.validationHook));
    }

    modifier whenUint256MaxDivTotalSupplyLEUniV4MaxTick() {
        _;
    }

    function test_WhenFloorPriceGTComputedMaxBidPrice(
        AuctionFuzzConstructorParams memory _params,
        uint256 _tickSpacing,
        uint256 _floorPrice,
        uint128 _totalSupply
    ) external whenUint256MaxDivTotalSupplyGEUniV4MaxTick {
        // it reverts with {FloorPriceAboveMaxBidPrice}

        AuctionFuzzConstructorParams memory mParams = validAuctionConstructorInputs(_params);
        // Set total supply such that the computed max bid price is less than the ConstantsLib.MAX_BID_PRICE
        mParams.totalSupply =
            uint128(bound(_totalSupply, type(uint256).max / ConstantsLib.MAX_BID_PRICE + 1, type(uint128).max));
        uint256 computedMaxBidPrice = type(uint256).max / mParams.totalSupply;
        mParams.parameters.floorPrice = bound(_floorPrice, computedMaxBidPrice + 1, type(uint256).max);
        // Easy default to pass the tick boundary check
        mParams.parameters.tickSpacing = mParams.parameters.floorPrice;

        vm.expectRevert(
            abi.encodeWithSelector(
                IAuction.FloorPriceAboveMaxBidPrice.selector, mParams.parameters.floorPrice, computedMaxBidPrice
            )
        );
        new Auction(mParams.token, mParams.totalSupply, mParams.parameters);
    }
}
