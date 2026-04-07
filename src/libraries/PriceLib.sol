// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ConstantsLib} from './ConstantsLib.sol';
import {FixedPoint96} from './FixedPoint96.sol';
import {ValueX7, ValueX7Lib} from './ValueX7Lib.sol';
import {FixedPointMathLib} from 'solady/utils/FixedPointMathLib.sol';

/// @title PriceLib
/// @notice Prices are denominated in currency per token (currency/token), in Q96 fixed-point form.
library PriceLib {
    using FixedPointMathLib for uint256;

    /// @notice Divide currency by a price into tokens, rounding up
    /// @param _currencyQ96 The currency to convert, in Q96 representation
    /// @param _priceQ96 The price to convert over, in Q96 representation
    /// @return The tokens, in Q96 representation
    function toTokensRoundingUp(uint256 _currencyQ96, uint256 _priceQ96) internal pure returns (uint256) {
        return _currencyQ96.fullMulDivUp(FixedPoint96.Q96, _priceQ96);
    }

    /// @notice Divide currency by tokens into a price, rounding up
    /// @param _currencyQ96 The currency to convert, in Q96 representation
    /// @param _tokensQ96 The number of tokens to convert over, in Q96 representation
    /// @return The price, in Q96 representation
    function toPriceRoundingUp(uint256 _currencyQ96, uint256 _tokensQ96) internal pure returns (uint256) {
        return _currencyQ96.fullMulDivUp(FixedPoint96.Q96, _tokensQ96);
    }
}
