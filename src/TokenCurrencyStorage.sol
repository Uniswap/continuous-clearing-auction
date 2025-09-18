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
    Currency public immutable currency;
    /// @notice The token being sold in the auction
    IERC20Minimal public immutable token;
    /// @notice The total supply of tokens to sell
    uint256 public immutable totalSupply;
    /// @notice The total supply of tokens to sell, scaled up to a ValueX7
    /// @dev The auction does not support selling more than type(uint256).max / MPSLib.MPS (1e7) tokens
    ValueX7 internal immutable totalSupplyX7;
    /// @notice The recipient of any unsold tokens at the end of the auction
    address public immutable tokensRecipient;
    /// @notice The recipient of the raised Currency from the auction
    address public immutable fundsRecipient;
    /// @notice The minimum portion (in MPS) of the total supply that must be sold
    uint24 public immutable graduationThresholdMps;

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
        token = IERC20Minimal(_token);
        totalSupply = _totalSupply;
        totalSupplyX7 = uint256(_totalSupply).scaleUpToX7();
        currency = Currency.wrap(_currency);
        tokensRecipient = _tokensRecipient;
        fundsRecipient = _fundsRecipient;
        graduationThresholdMps = _graduationThresholdMps;

        if (totalSupply == 0) revert TotalSupplyIsZero();
        if (fundsRecipient == address(0)) revert FundsRecipientIsZero();
        if (graduationThresholdMps > MPSLib.MPS) revert InvalidGraduationThresholdMps();
    }

    function _sweepCurrency(uint256 amount) internal {
        sweepCurrencyBlock = block.number;
        currency.transfer(fundsRecipient, amount);
        emit CurrencySwept(fundsRecipient, amount);
    }

    function _sweepUnsoldTokens(uint256 amount) internal {
        sweepUnsoldTokensBlock = block.number;
        if (amount > 0) {
            Currency.wrap(address(token)).transfer(tokensRecipient, amount);
        }
        emit TokensSwept(tokensRecipient, amount);
    }
}
