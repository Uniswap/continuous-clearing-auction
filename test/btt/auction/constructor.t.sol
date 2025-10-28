// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {AuctionFuzzConstructorParams, BttBase} from '../BttBase.sol';
import {FixedPointMathLib} from 'solady/utils/FixedPointMathLib.sol';
import {Auction} from 'src/Auction.sol';
import {IAuction} from 'src/interfaces/IAuction.sol';
import {ConstantsLib} from 'src/libraries/ConstantsLib.sol';
import {FixedPoint96} from 'src/libraries/FixedPoint96.sol';

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
