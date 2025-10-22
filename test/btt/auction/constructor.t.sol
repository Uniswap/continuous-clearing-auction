// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {AuctionFuzzConstructorParams, BttBase} from '../BttBase.sol';

import {FixedPointMathLib} from 'solady/utils/FixedPointMathLib.sol';
import {Auction} from 'src/Auction.sol';
import {IAuction} from 'src/interfaces/IAuction.sol';
import {ConstantsLib} from 'src/libraries/ConstantsLib.sol';

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

    function test_WhenTypeUint256MaxDivTotalSupplyGTUniV4MaxTick(AuctionFuzzConstructorParams memory _params)
        external
        setupAuctionConstructorParams(_params)
    {
        // it sets bid max price to be uni v4 max tick

        // Assume total supply to be tiny - uniswap max tick is 224 bits, to anything less than a uint32 should do it
        _params.totalSupply = uint128(bound(_params.totalSupply, 1, type(uint32).max));

        Auction auction = new Auction(_params.token, _params.totalSupply, _params.parameters);

        assertEq(auction.MAX_BID_PRICE(), ConstantsLib.MAX_BID_PRICE);
    }

    function test_WhenTypeUint256MaxDivTotalSupplyLTUniV4MaxTick(AuctionFuzzConstructorParams memory _params)
        external
        setupAuctionConstructorParams(_params)
    {
        // it sets bid max price to be type(uint256).max / totalSupply

        // Anything greater than a uint32 should do it
        _params.totalSupply = uint128(bound(_params.totalSupply, uint128(type(uint40).max), type(uint128).max));
        uint256 expectedBidMaxPrice = type(uint256).max / _params.totalSupply;

        Auction auction = new Auction(_params.token, _params.totalSupply, _params.parameters);

        assertEq(auction.MAX_BID_PRICE(), expectedBidMaxPrice);
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

        uint256 expectedBidMaxPrice =
            FixedPointMathLib.min(type(uint256).max / _params.totalSupply, ConstantsLib.MAX_BID_PRICE);

        Auction auction = new Auction(_params.token, _params.totalSupply, _params.parameters);

        assertEq(auction.claimBlock(), _params.parameters.claimBlock);
        assertEq(address(auction.validationHook()), _params.parameters.validationHook);
        assertEq(auction.MAX_BID_PRICE(), expectedBidMaxPrice);
    }
}
