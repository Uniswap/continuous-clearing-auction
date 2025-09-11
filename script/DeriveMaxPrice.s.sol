// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {FixedPoint96} from '../src/libraries/FixedPoint96.sol';
import {Script} from 'forge-std/Script.sol';
import {console2} from 'forge-std/console2.sol';
import {FixedPointMathLib} from 'solady/utils/FixedPointMathLib.sol';

contract DeriveMaxPriceScript is Script {
    using FixedPointMathLib for uint160;
    /// Copied from https://github.com/Uniswap/v4-core/blob/main/src/libraries/TickMath.sol#L30C1-L33C98
    /// @dev The minimum value that can be returned from #getSqrtPriceAtTick. Equivalent to getSqrtPriceAtTick(MIN_TICK)

    uint160 internal constant MIN_SQRT_PRICE = 4_295_128_739;
    /// @dev The maximum value that can be returned from #getSqrtPriceAtTick. Equivalent to getSqrtPriceAtTick(MAX_TICK)
    uint160 internal constant MAX_SQRT_PRICE = 1_461_446_703_485_210_103_287_273_052_203_988_822_378_723_970_342;

    function run() public {
        console2.log(
            'MAX_SQRT_PRICE.fullMulDiv(MAX_SQRT_PRICE, FixedPoint96.Q96)',
            MAX_SQRT_PRICE.fullMulDiv(MAX_SQRT_PRICE, FixedPoint96.Q96)
        );
        console2.log('MIN_SQRT_PRICE ** 2', MIN_SQRT_PRICE ** 2);
    }
}
