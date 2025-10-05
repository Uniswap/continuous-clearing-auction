// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ITokenCurrencyStorage} from './interfaces/ITokenCurrencyStorage.sol';
import {IERC20Minimal} from './interfaces/external/IERC20Minimal.sol';
import {Currency, CurrencyLibrary} from './libraries/CurrencyLibrary.sol';
import {SupplyLib} from './libraries/SupplyLib.sol';
import {ValueX7, ValueX7Lib} from './libraries/ValueX7Lib.sol';
import {ValueX7X7, ValueX7X7Lib} from './libraries/ValueX7X7Lib.sol';
import {FixedPointMathLib} from 'solady/utils/FixedPointMathLib.sol';

/// @title TokenCurrencyStorage
abstract contract TokenCurrencyStorage is ITokenCurrencyStorage {
    using FixedPointMathLib for uint256;
    using CurrencyLibrary for Currency;
    using ValueX7Lib for *;
    using ValueX7X7Lib for *;
    using SupplyLib for *;

    /// @notice The currency being raised in the auction
    Currency internal immutable CURRENCY;
    /// @notice The token being sold in the auction
    IERC20Minimal internal immutable TOKEN;
    /// @notice The total supply of tokens to sell
    uint256 internal immutable TOTAL_SUPPLY;
    /// @notice The total supply of tokens to sell, scaled up to a ValueX7X7
    ValueX7X7 internal immutable TOTAL_SUPPLY_X7_X7;
    /// @notice The recipient of any unsold tokens at the end of the auction
    address internal immutable TOKENS_RECIPIENT;
    /// @notice The recipient of the raised Currency from the auction
    address internal immutable FUNDS_RECIPIENT;

    /// @notice The block at which the currency was swept
    uint256 public sweepCurrencyBlock;
    /// @notice The block at which the tokens were swept
    uint256 public sweepUnsoldTokensBlock;

    constructor(
        address _token,
        address _currency,
        uint256 _totalSupply,
        address _tokensRecipient,
        address _fundsRecipient
    ) {
        TOKEN = IERC20Minimal(_token);
        CURRENCY = Currency.wrap(_currency);
        TOTAL_SUPPLY = _totalSupply;
        if (_totalSupply > SupplyLib.MAX_TOTAL_SUPPLY) revert TotalSupplyIsTooLarge();
        if (_totalSupply == 0) revert TotalSupplyIsZero();
        TOTAL_SUPPLY_X7_X7 = _totalSupply.toX7X7();
        TOKENS_RECIPIENT = _tokensRecipient;
        FUNDS_RECIPIENT = _fundsRecipient;

        if (_token == address(0)) revert TokenIsAddressZero();
        if (_token == address(_currency)) revert TokenAndCurrencyCannotBeTheSame();
        if (TOKENS_RECIPIENT == address(0)) revert TokensRecipientIsZero();
        if (FUNDS_RECIPIENT == address(0)) revert FundsRecipientIsZero();
    }

    function _sweepCurrency(uint256 amount) internal {
        sweepCurrencyBlock = block.number;
        CURRENCY.transfer(FUNDS_RECIPIENT, amount);
        emit CurrencySwept(FUNDS_RECIPIENT, amount);
    }

    function _sweepUnsoldTokens(uint256 amount) internal {
        sweepUnsoldTokensBlock = block.number;
        if (amount > 0) {
            Currency.wrap(address(TOKEN)).transfer(TOKENS_RECIPIENT, amount);
        }
        emit TokensSwept(TOKENS_RECIPIENT, amount);
    }

    // Getters
    /// @inheritdoc ITokenCurrencyStorage
    function currency() external view override(ITokenCurrencyStorage) returns (Currency) {
        return CURRENCY;
    }

    /// @inheritdoc ITokenCurrencyStorage
    function token() external view override(ITokenCurrencyStorage) returns (IERC20Minimal) {
        return TOKEN;
    }

    /// @inheritdoc ITokenCurrencyStorage
    function totalSupply() external view override(ITokenCurrencyStorage) returns (uint256) {
        return TOTAL_SUPPLY;
    }

    /// @inheritdoc ITokenCurrencyStorage
    function tokensRecipient() external view override(ITokenCurrencyStorage) returns (address) {
        return TOKENS_RECIPIENT;
    }

    /// @inheritdoc ITokenCurrencyStorage
    function fundsRecipient() external view override(ITokenCurrencyStorage) returns (address) {
        return FUNDS_RECIPIENT;
    }
}
