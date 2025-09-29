// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

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
    /// @dev The auction does not support selling more than type(uint128).max tokens
    uint128 public immutable totalSupply;
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
    /// @notice The data to pass to the fundsRecipient
    bytes public fundsRecipientData;

    constructor(
        address _token,
        address _currency,
        uint128 _totalSupply,
        address _tokensRecipient,
        address _fundsRecipient,
        uint24 _graduationThresholdMps,
        bytes memory _fundsRecipientData
    ) {
        token = IERC20Minimal(_token);
        totalSupply = _totalSupply;
        currency = Currency.wrap(_currency);
        tokensRecipient = _tokensRecipient;
        fundsRecipient = _fundsRecipient;
        graduationThresholdMps = _graduationThresholdMps;
        fundsRecipientData = _fundsRecipientData;

        if (totalSupply == 0) revert TotalSupplyIsZero();
        if (fundsRecipient == address(0)) revert FundsRecipientIsZero();
        if (graduationThresholdMps > AuctionStepLib.MPS) revert InvalidGraduationThresholdMps();
    }

    function _sweepCurrency(uint256 amount) internal {
        sweepCurrencyBlock = block.number;
        // First transfer the currency to the fundsRecipient
        currency.transfer(fundsRecipient, amount);
        // Then if fundsRecipientData is set and is a contract, call it
        if (fundsRecipientData.length > 0 && address(fundsRecipient).code.length > 0 && fundsRecipient != address(this))
        {
            (bool success, bytes memory result) = address(fundsRecipient).call(fundsRecipientData);
            if (!success) {
                // bubble up the revert reason
                assembly {
                    revert(add(result, 0x20), mload(result))
                }
            }
        }
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
