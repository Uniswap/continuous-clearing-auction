// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {FixedPoint96} from './FixedPoint96.sol';
import {Math} from '@openzeppelin/contracts/utils/math/Math.sol';
import {FixedPointMathLib} from 'solady/utils/FixedPointMathLib.sol';

/// @title PriceLib
/// @notice Library for converting between currency, tokens, and prices in Q96 representation
library PriceLib {
    using FixedPointMathLib for uint256;

    /// @notice Convert currency to tokens over a given price, rounding up
    /// @param _currencyQ96 The currency to convert, in Q96 representation
    /// @param _priceQ96 The price to convert over, in Q96 representation
    /// @return The tokens, in Q96 representation
    function toTokensRoundingUp(uint256 _currencyQ96, uint256 _priceQ96) internal pure returns (uint256) {
        return _currencyQ96.fullMulDivUp(FixedPoint96.Q96, _priceQ96);
    }

    /// @notice Convert currency to tokens over a given price, rounding down
    /// @param _currencyQ96 The currency to convert, in Q96 representation
    /// @param _priceQ96 The price to convert over, in Q96 representation
    /// @return The tokens, in Q96 representation
    function toTokensRoundingDown(uint256 _currencyQ96, uint256 _priceQ96) internal pure returns (uint256) {
        return _currencyQ96.fullMulDiv(FixedPoint96.Q96, _priceQ96);
    }

    /// @notice Convert tokens to currency over a given price, rounding up
    /// @param _tokensQ96 The tokens to convert, in Q96 representation
    /// @param _priceQ96 The price to convert over, in Q96 representation
    /// @return The currency, in Q96 representation
    function toCurrencyRoundingUp(uint256 _tokensQ96, uint256 _priceQ96) internal pure returns (uint256) {
        return _tokensQ96.fullMulDivUp(_priceQ96, FixedPoint96.Q96);
    }

    /// @notice Convert tokens to currency over a given price, rounding down
    /// @param _tokensQ96 The tokens to convert, in Q96 representation
    /// @param _priceQ96 The price to convert over, in Q96 representation
    /// @return The currency, in Q96 representation
    function toCurrencyRoundingDown(uint256 _tokensQ96, uint256 _priceQ96) internal pure returns (uint256) {
        return _tokensQ96.fullMulDiv(_priceQ96, FixedPoint96.Q96);
    }

    /// @notice Convert currency to price over a given number of tokens, rounding up
    /// @param _currencyQ96 The currency to convert, in Q96 representation
    /// @param _tokensQ96 The number of tokens to convert over, in Q96 representation
    /// @return The price, in Q96 representation
    function toPriceRoundingUp(uint256 _currencyQ96, uint256 _tokensQ96) internal pure returns (uint256) {
        return _currencyQ96.fullMulDivUp(FixedPoint96.Q96, _tokensQ96);
    }

    /// @notice Convert currency to price over a given number of tokens, rounding down
    /// @param _currencyQ96 The currency to convert, in Q96 representation
    /// @param _tokensQ96 The number of tokens to convert over, in Q96 representation
    /// @return The price, in Q96 representation
    function toPriceRoundingDown(uint256 _currencyQ96, uint256 _tokensQ96) internal pure returns (uint256) {
        return _currencyQ96.fullMulDiv(FixedPoint96.Q96, _tokensQ96);
    }
}
