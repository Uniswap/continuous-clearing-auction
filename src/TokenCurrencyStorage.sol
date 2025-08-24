// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {ITokenCurrencyStorage} from './interfaces/ITokenCurrencyStorage.sol';
import {IERC20Minimal} from './interfaces/external/IERC20Minimal.sol';
import {Currency, CurrencyLibrary} from './libraries/CurrencyLibrary.sol';
import {FixedPoint96} from './libraries/FixedPoint96.sol';

import {console2} from 'forge-std/console2.sol';
import {FixedPointMathLib} from 'solady/utils/FixedPointMathLib.sol';

abstract contract TokenCurrencyStorage is ITokenCurrencyStorage {
    using CurrencyLibrary for Currency;
    using FixedPointMathLib for uint256;

    /// @notice The currency being raised in the auction
    Currency public immutable currency;
    /// @notice The token being sold in the auction
    IERC20Minimal public immutable token;
    /// @notice The total supply of tokens to sell
    uint256 public immutable totalSupply;
    /// @notice The recipient of any unsold tokens at the end of the auction
    address public immutable tokensRecipient;
    /// @notice The recipient of the raised Currency from the auction
    address public immutable fundsRecipient;

    /// @notice Whether the currency is sorted before the token in the auction
    /// @dev If true, then currency is token0 and token is token1. Vice versa if false.
    bool public immutable currencyIsToken0;

    constructor(
        address _token,
        address _currency,
        uint256 _totalSupply,
        address _tokensRecipient,
        address _fundsRecipient
    ) {
        token = IERC20Minimal(_token);
        totalSupply = _totalSupply;
        currency = Currency.wrap(_currency);
        tokensRecipient = _tokensRecipient;
        fundsRecipient = _fundsRecipient;

        if (totalSupply == 0) revert TotalSupplyIsZero();
        if (fundsRecipient == address(0)) revert FundsRecipientIsZero();

        currencyIsToken0 = address(Currency.unwrap(currency)) < address(token);
    }

    /// @notice Converts two amounts into a price
    /// @dev Price is always expressed as token1 / token0
    function _toPrice(uint256 currencyAmount, uint256 tokenAmount) internal view returns (uint256) {
        // Price will be 0 or undefined if either amount is 0 so return here
        if (currencyAmount == 0 || tokenAmount == 0) return 0;
        if (currencyIsToken0) {
            return tokenAmount.fullMulDiv(FixedPoint96.Q96, currencyAmount);
        } else {
            return currencyAmount.fullMulDiv(FixedPoint96.Q96, tokenAmount);
        }
    }
}
