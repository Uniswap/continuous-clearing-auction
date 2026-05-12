// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IAuctionStorage} from './interfaces/IAuctionStorage.sol';
import {IERC20Minimal} from './interfaces/external/IERC20Minimal.sol';
import {ConstantsLib} from './libraries/ConstantsLib.sol';
import {Currency, CurrencyLibrary} from './libraries/CurrencyLibrary.sol';
import {FixedPoint96} from './libraries/FixedPoint96.sol';
import {ValueX7} from './libraries/ValueX7Lib.sol';

/// @title AuctionStorage
/// @notice Abstract contract for managing auction storage including token/currency config and auction state
abstract contract AuctionStorage is IAuctionStorage {
    using CurrencyLibrary for Currency;

    // Immutable token/currency config

    /// @notice The currency being raised in the auction
    Currency internal immutable CURRENCY;
    /// @notice The token being sold in the auction
    IERC20Minimal internal immutable TOKEN;
    /// @notice The amount of tokens to sell in the auction
    uint128 internal immutable TOTAL_SUPPLY;
    /// @notice The total supply of tokens to sell in Q96 representation, scaled up by X7
    ValueX7 internal immutable TOTAL_SUPPLY_Q96X7;
    /// @notice The recipient of any unsold tokens at the end of the auction
    address internal immutable TOKENS_RECIPIENT;
    /// @notice The recipient of the raised Currency from the auction
    address internal immutable FUNDS_RECIPIENT;
    /// @notice The amount of currency required to be raised for the auction
    ///         to graduate in Q96 form, scaled up by X7
    ValueX7 internal immutable REQUIRED_CURRENCY_RAISED_Q96X7;

    // Mutable auction state

    /// @notice The total currency raised in the auction in Q96 representation, scaled up by X7
    ValueX7 internal $currencyRaisedQ96X7;
    /// @notice The total tokens sold in the auction so far, in Q96 representation, scaled up by X7
    ValueX7 internal $totalClearedQ96X7;
    /// @notice The sum of currency demand in ticks above the clearing price
    /// @dev This will increase every time a new bid is submitted, and decrease when bids are outbid.
    uint256 internal $sumCurrencyDemandAboveClearingQ96;
    /// @notice The most up to date clearing price, set on each call to `checkpoint`
    /// @dev This can be incremented manually by calling `forceIterateOverTicks`
    uint256 internal $clearingPrice;
    /// @notice Whether TOTAL_SUPPLY has been received
    bool internal $_tokensReceived;

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
        TOTAL_SUPPLY_Q96X7 = ValueX7.wrap((uint256(_totalSupply) << FixedPoint96.RESOLUTION) * ConstantsLib.MPS);
        TOKENS_RECIPIENT = _tokensRecipient;
        FUNDS_RECIPIENT = _fundsRecipient;
        REQUIRED_CURRENCY_RAISED_Q96X7 =
            ValueX7.wrap((uint256(_requiredCurrencyRaised) << FixedPoint96.RESOLUTION) * ConstantsLib.MPS);
    }

    // Internal sweep functions

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

    // View functions

    /// @inheritdoc IAuctionStorage
    function currencyRaised() public view returns (uint256) {
        return (ValueX7.unwrap($currencyRaisedQ96X7) / FixedPoint96.Q96) / ConstantsLib.MPS;
    }

    /// @inheritdoc IAuctionStorage
    function currencyRaisedQ96X7() public view returns (ValueX7) {
        return $currencyRaisedQ96X7;
    }

    /// @inheritdoc IAuctionStorage
    function sumCurrencyDemandAboveClearingQ96() public view returns (uint256) {
        return $sumCurrencyDemandAboveClearingQ96;
    }

    /// @inheritdoc IAuctionStorage
    function totalClearedQ96X7() public view returns (ValueX7) {
        return $totalClearedQ96X7;
    }

    /// @inheritdoc IAuctionStorage
    function totalCleared() public view returns (uint256) {
        return (ValueX7.unwrap($totalClearedQ96X7) / FixedPoint96.Q96) / ConstantsLib.MPS;
    }

    /// @inheritdoc IAuctionStorage
    function remainingSupplyQ96X7() public view returns (ValueX7) {
        return _remainingSupplyQ96X7();
    }

    function _remainingSupplyQ96X7() internal view returns (ValueX7) {
        return TOTAL_SUPPLY_Q96X7.sub($totalClearedQ96X7);
    }

    /// @inheritdoc IAuctionStorage
    function remainingSupply() public view returns (uint256) {
        return (ValueX7.unwrap(_remainingSupplyQ96X7()) / FixedPoint96.Q96) / ConstantsLib.MPS;
    }
}
