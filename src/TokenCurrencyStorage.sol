// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ITokenCurrencyStorage} from './interfaces/ITokenCurrencyStorage.sol';
import {IERC20Minimal} from './interfaces/external/IERC20Minimal.sol';
import {Currency, CurrencyLibrary} from './libraries/CurrencyLibrary.sol';
import {MPSLib, ValueX7} from './libraries/MPSLib.sol';

/// @title TokenCurrencyStorage
abstract contract TokenCurrencyStorage is ITokenCurrencyStorage {
    using CurrencyLibrary for Currency;
    using MPSLib for uint256;

    /// @notice The currency being raised in the auction
    Currency internal immutable CURRENCY;
    /// @notice The token being sold in the auction
    IERC20Minimal internal immutable TOKEN;
    /// @notice The total supply of tokens to sell
    uint256 internal immutable TOTAL_SUPPLY;
    /// @notice The total supply of tokens to sell, scaled up to a ValueX7
    /// @dev The auction does not support selling more than type(uint256).max / MPSLib.MPS (1e7) tokens
    ValueX7 internal immutable TOTAL_SUPPLY_X7;
    /// @notice The recipient of any unsold tokens at the end of the auction
    address internal immutable TOKENS_RECIPIENT;
    /// @notice The recipient of the raised Currency from the auction
    address internal immutable FUNDS_RECIPIENT;
    /// @notice The minimum portion (in MPS) of the total supply that must be sold
    uint24 internal immutable GRADUATION_THRESHOLD_MPS;

    /// @notice The block at which the currency was swept
    uint256 public sweepCurrencyBlock;
    /// @notice The block at which the tokens were swept
    uint256 public sweepUnsoldTokensBlock;

    constructor(
        address _token,
        address _currency,
        uint256 _totalSupply,
        address _tokensRecipient,
        address _fundsRecipient,
        uint24 _graduationThresholdMps
    ) {
        TOKEN = IERC20Minimal(_token);
        TOTAL_SUPPLY = _totalSupply;
        TOTAL_SUPPLY_X7 = _totalSupply.scaleUpToX7();
        CURRENCY = Currency.wrap(_currency);
        TOKENS_RECIPIENT = _tokensRecipient;
        FUNDS_RECIPIENT = _fundsRecipient;
        GRADUATION_THRESHOLD_MPS = _graduationThresholdMps;

        if (TOTAL_SUPPLY == 0) revert TotalSupplyIsZero();
        if (FUNDS_RECIPIENT == address(0)) revert FundsRecipientIsZero();
        if (GRADUATION_THRESHOLD_MPS > MPSLib.MPS) revert InvalidGraduationThresholdMps();
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

    /// @inheritdoc ITokenCurrencyStorage
    function graduationThresholdMps() external view override(ITokenCurrencyStorage) returns (uint24) {
        return GRADUATION_THRESHOLD_MPS;
    }
}
