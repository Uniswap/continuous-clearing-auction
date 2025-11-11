// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ConstantsLib} from 'continuous-clearing-auction/libraries/ConstantsLib.sol';
import {MaxBidPriceLib} from 'continuous-clearing-auction/libraries/MaxBidPriceLib.sol';
import {Test} from 'forge-std/Test.sol';

contract MaxBidPriceLibTest is Test {
    function test_WhenTotalSupplyIsLELowerTotalSupplyThreshold_ThenMaxBidPriceIsMaxV4Price(uint128 _totalSupply)
        public
    {
        // it returns MaxBidPriceLib.MAX_V4_PRICE

        _totalSupply = uint128(bound(_totalSupply, 1, MaxBidPriceLib.LOWER_TOTAL_SUPPLY_THRESHOLD));
        uint256 maxBidPrice = MaxBidPriceLib.maxBidPrice(_totalSupply);
        assertEq(maxBidPrice, MaxBidPriceLib.MAX_V4_PRICE);
    }

    function test_WhenTotalSupplyIsGTLowerTotalSupplyThreshold(uint128 _totalSupply) public {
        // it returns the calculated max bid price which is less than MaxBidPriceLib.MAX_V4_PRICE

        _totalSupply = uint128(
            bound(_totalSupply, MaxBidPriceLib.LOWER_TOTAL_SUPPLY_THRESHOLD + 1, ConstantsLib.MAX_TOTAL_SUPPLY)
        );
        uint256 maxBidPrice = MaxBidPriceLib.maxBidPrice(_totalSupply);

        // calculated max bid price must be less than MaxBidPriceLib.MAX_V4_PRICE
        assertLt(maxBidPrice, MaxBidPriceLib.MAX_V4_PRICE);
    }
}
