// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ITokenCurrencyStorage} from './interfaces/ITokenCurrencyStorage.sol';
import {IERC20Minimal} from './interfaces/external/IERC20Minimal.sol';
import {Currency, CurrencyLibrary} from './libraries/CurrencyLibrary.sol';

import {MPSLib} from './libraries/MPSLib.sol';
import {ValueX7, ValueX7Lib} from './libraries/ValueX7Lib.sol';
import {ValueX7X7, ValueX7X7Lib} from './libraries/ValueX7X7Lib.sol';
import {ConstantsLib} from './libraries/ConstantsLib.sol';

/// @title TokenCurrencyStorage
abstract contract TokenCurrencyStorage is ITokenCurrencyStorage {
    using CurrencyLibrary for Currency;
    using ValueX7Lib for *;
    using ValueX7X7Lib for *;

    /// @notice The currency being raised in the auction
    Currency internal immutable CURRENCY;
    /// @notice The token being sold in the auction
    IERC20Minimal internal immutable TOKEN;
    /// @notice The total supply of tokens to sell
    uint256 internal immutable TOTAL_SUPPLY;
    /// @notice The total supply of tokens to sell, scaled up to a ValueX7
    /// @dev The auction does not support selling more than type(uint256).max / (1e7 ** 2) tokens
    ValueX7X7 internal immutable TOTAL_SUPPLY_X7_X7;
    /// @notice Whether the total supply is less than uint232 max
    /// @dev If true, we can pack X7X7 values along with uint24 cumulativeMps values into the same word
    bool internal immutable TOTAL_SUPPLY_X7_X7_LESS_THAN_UINT_232_MAX;
    /// @notice Bit mask for the lower 232 bits of a uint256
    uint256 internal constant MASK_LOWER_232_BITS = 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffff;
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
        if (_totalSupply > ConstantsLib.X7X7_UPPER_BOUND) revert TotalSupplyIsGreaterThanX7X7UpperBound();

        TOKEN = IERC20Minimal(_token);
        TOTAL_SUPPLY = _totalSupply;
        TOTAL_SUPPLY_X7_X7 = _totalSupply.scaleUpToX7().scaleUpToX7X7();
        TOTAL_SUPPLY_X7_X7_LESS_THAN_UINT_232_MAX = ValueX7X7.unwrap(TOTAL_SUPPLY_X7_X7) >> 232 == 0;
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
