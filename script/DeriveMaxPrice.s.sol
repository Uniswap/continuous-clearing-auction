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

    function run() public pure {
        console2.log(
            'MAX_SQRT_PRICE.fullMulDiv(MAX_SQRT_PRICE, FixedPoint96.Q96)',
            MAX_SQRT_PRICE.fullMulDiv(MAX_SQRT_PRICE, FixedPoint96.Q96)
        );
        // 1 << 96 / K = MIN_SQRT_PRICE
        // K = 1 << 96 / MIN_SQRT_PRICE
        // (1 << 96 / K) ** 2 = MIN_SQRT_PRICE ** 2
        // Finally, need to shift it to the right 96 bits to get the price, which is zero.
        // This means that the MIN_SQRT_PRICE ^ 2 is so small that it cannot be represented in a 64.96 fixed point number.
        // Thus, the smallest value representable in a X96 value, 1, is greater than MIN_SQRT_PRICE ^ 2, can be used as a minimum floor price
        // This is why in the contract we require the floor price to be > 0, or at minimum, 1.
        uint256 k = (1 << FixedPoint96.RESOLUTION) / MIN_SQRT_PRICE;
        console2.log(
            '(((1 << 96) / K) ** 2) >> 96', (((1 << FixedPoint96.RESOLUTION) / k) ** 2) >> FixedPoint96.RESOLUTION
        );
    }
}
