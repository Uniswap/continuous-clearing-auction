// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ITokenCurrencyStorage} from './interfaces/ITokenCurrencyStorage.sol';
import {IERC20Minimal} from './interfaces/external/IERC20Minimal.sol';
import {ConstantsLib} from './libraries/ConstantsLib.sol';
import {Currency, CurrencyLibrary} from './libraries/CurrencyLibrary.sol';
import {FixedPoint96} from './libraries/FixedPoint96.sol';
import {ValueX7, ValueX7Lib} from './libraries/ValueX7Lib.sol';

/// @title TokenCurrencyStorage
abstract contract TokenCurrencyStorage is ITokenCurrencyStorage {
    using ValueX7Lib for *;
    using CurrencyLibrary for Currency;

    /// @notice The currency being raised in the auction
    Currency internal immutable CURRENCY;
    /// @notice The token being sold in the auction
    IERC20Minimal internal immutable TOKEN;
    /// @notice The total supply of tokens to sell
    uint128 internal immutable TOTAL_SUPPLY;
    /// @notice The recipient of any unsold tokens at the end of the auction
    address internal immutable TOKENS_RECIPIENT;
    /// @notice The recipient of the raised Currency from the auction
    address internal immutable FUNDS_RECIPIENT;
    /// @notice The amount of currency required to be raised for the auction
    ///         to graduate in Q96 form, scaled up by X7
    ValueX7 internal immutable REQUIRED_CURRENCY_RAISED_Q96_X7;

    /// @notice The block at which the currency was swept
    uint256 public sweepCurrencyBlock;
    /// @notice The block at which the tokens were swept
    uint256 public sweepUnsoldTokensBlock;

    constructor(
        address _token,
        address _currency,
        uint128 _totalSupply,
        address _tokensRecipient,
        address _fundsRecipient,
        uint128 _requiredCurrencyRaised
    ) {
        if (_token == address(0)) revert TokenIsAddressZero();
        if (_token == _currency) revert TokenAndCurrencyCannotBeTheSame();
        if (_totalSupply == 0) revert TotalSupplyIsZero();
        if (_totalSupply > ConstantsLib.MAX_TOTAL_SUPPLY) revert TotalSupplyIsTooLarge();
        if (_tokensRecipient == address(0)) revert TokensRecipientIsZero();
        if (_fundsRecipient == address(0)) revert FundsRecipientIsZero();

        TOKEN = IERC20Minimal(_token);
        CURRENCY = Currency.wrap(_currency);
        TOTAL_SUPPLY = _totalSupply;
        TOKENS_RECIPIENT = _tokensRecipient;
        FUNDS_RECIPIENT = _fundsRecipient;
        REQUIRED_CURRENCY_RAISED_Q96_X7 = (uint256(_requiredCurrencyRaised) << FixedPoint96.RESOLUTION).scaleUpToX7();
    }

    function _sweepCurrency(uint256 _blockNumberIsh, uint256 _amount) internal {
        sweepCurrencyBlock = _blockNumberIsh;
        if (_amount > 0) {
            CURRENCY.transfer(FUNDS_RECIPIENT, _amount);
        }
        emit CurrencySwept(FUNDS_RECIPIENT, _amount);
    }

    function _sweepUnsoldTokens(uint256 _blockNumberIsh, uint256 _amount) internal {
        sweepUnsoldTokensBlock = _blockNumberIsh;
        if (_amount > 0) {
            Currency.wrap(address(TOKEN)).transfer(TOKENS_RECIPIENT, _amount);
        }
        emit TokensSwept(TOKENS_RECIPIENT, _amount);
    }
}
