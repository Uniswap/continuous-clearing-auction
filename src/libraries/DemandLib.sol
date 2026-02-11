// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {FixedPoint96} from './FixedPoint96.sol';
import {PriceLib} from './PriceLib.sol';
import {ValueX7} from './ValueX7Lib.sol';
import {Math} from '@openzeppelin/contracts/utils/math/Math.sol';

/// @title DemandLib
/// @notice Library for demand calculations
library DemandLib {
    using Math for uint256;
    using PriceLib for uint256;

    /// @notice Returns true if the demand value is greater than or equal to
    function gte(uint256 _demandQ96, uint256 _supplyQ96X7, uint256 _priceQ96) internal pure returns (bool) {
        (uint256 highLhs, uint256 lowLhs) = Math.mul512(_demandQ96, FixedPoint96.Q96);
        (uint256 highRhs, uint256 lowRhs) = Math.mul512(_supplyQ96X7, _priceQ96);
        return highLhs > highRhs || (highLhs == highRhs && lowLhs > lowRhs);
    }
}
