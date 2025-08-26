// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {ITokenCurrencyStorage} from './interfaces/ITokenCurrencyStorage.sol';
import {IERC20Minimal} from './interfaces/external/IERC20Minimal.sol';

import {AuctionStepLib} from './libraries/AuctionStepLib.sol';
import {Currency, CurrencyLibrary} from './libraries/CurrencyLibrary.sol';

/// @title TokenCurrencyStorage
abstract contract TokenCurrencyStorage is ITokenCurrencyStorage {
    using CurrencyLibrary for Currency;

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
    /// @notice The minimum percentage of the total supply that must be sold
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
        currency = Currency.wrap(_currency);
        tokensRecipient = _tokensRecipient;
        fundsRecipient = _fundsRecipient;
        graduationThresholdMps = _graduationThresholdMps;

        if (totalSupply == 0) revert TotalSupplyIsZero();
        if (fundsRecipient == address(0)) revert FundsRecipientIsZero();
        if (graduationThresholdMps > AuctionStepLib.MPS) revert InvalidGraduationThresholdMps();
    }

    /// @notice Whether the auction has graduated (sold more than the graduation threshold)
    /// @dev Should only be called after the auction has ended
    /// @param _totalCleared The total amount of tokens cleared, must be the final checkpoint of the auction
    function _isGraduated(uint256 _totalCleared) internal view returns (bool) {
        return _totalCleared >= ((totalSupply * graduationThresholdMps) / AuctionStepLib.MPS);
    }

    /// @dev The currency can only be swept if they have not been already, and before the claim block
    function _canSweepCurrency() internal view virtual returns (bool) {
        return sweepCurrencyBlock == 0;
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
