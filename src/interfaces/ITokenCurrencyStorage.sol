// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Currency} from '../libraries/CurrencyLibrary.sol';
import {ValueX7} from '../libraries/ValueX7Lib.sol';
import {ValueX7X7} from '../libraries/ValueX7X7Lib.sol';
import {IERC20Minimal} from './external/IERC20Minimal.sol';

/// @notice Interface for token and currency storage operations
interface ITokenCurrencyStorage {
    /// @notice Error thrown when the total supply is too large
    error TotalSupplyIsTooLarge();
    /// @notice Error thrown when the token is the native currency
    error TokenIsAddressZero();
    /// @notice Error thrown when the token and currency are the same
    error TokenAndCurrencyCannotBeTheSame();
    /// @notice Error thrown when the total supply is zero
    error TotalSupplyIsZero();
    /// @notice Error thrown when the funds recipient is the zero address
    error FundsRecipientIsZero();
    /// @notice Error thrown when the tokens recipient is the zero address
    error TokensRecipientIsZero();
    /// @notice Error thrown when the currency cannot be swept
    error CannotSweepCurrency();
    /// @notice Error thrown when the tokens cannot be swept
    error CannotSweepTokens();
    /// @notice Error thrown when the graduation threshold is invalid
    error InvalidGraduationThresholdMps();
    /// @notice Error thrown when the auction has not graduated
    error NotGraduated();
    /// @notice Error thrown when the funds recipient data cannot be decoded
    error FundsRecipientCallFailed();

    /// @notice Emitted when the tokens are swept
    /// @param tokensRecipient The address of the tokens recipient
    /// @param tokensAmount The amount of tokens swept
    event TokensSwept(address indexed tokensRecipient, uint256 tokensAmount);

    /// @notice Emitted when the currency is swept
    /// @param fundsRecipient The address of the funds recipient
    /// @param currencyAmount The amount of currency swept
    event CurrencySwept(address indexed fundsRecipient, uint256 currencyAmount);

    /// @notice The currency being raised in the auction
    function currency() external view returns (Currency);

    /// @notice The token being sold in the auction
    function token() external view returns (IERC20Minimal);

    /// @notice The total supply of tokens to sell
    function totalSupply() external view returns (uint256);

    /// @notice The recipient of any unsold tokens at the end of the auction
    function tokensRecipient() external view returns (address);

    /// @notice The recipient of the raised Currency from the auction
    function fundsRecipient() external view returns (address);

    /// @notice The minimum portion (in MPS) of the total supply that must be sold
    function graduationThresholdMps() external view returns (uint24);
}
