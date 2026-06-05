// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ValueX7} from '../libraries/ValueX7Lib.sol';

/// @notice Interface for auction storage operations
interface IAuctionStorage {
    /// @notice Error thrown when the token is the native currency
    error TokenIsAddressZero();
    /// @notice Error thrown when the token and currency are the same
    error TokenAndCurrencyCannotBeTheSame();
    /// @notice Error thrown when the total supply is zero
    error TotalSupplyIsZero();
    /// @notice Error thrown when the total supply is too large
    error TotalSupplyIsTooLarge();
    /// @notice Error thrown when the funds recipient is the zero address
    error FundsRecipientIsZero();
    /// @notice Error thrown when the tokens recipient is the zero address
    error TokensRecipientIsZero();
    /// @notice Error thrown when the currency cannot be swept
    error CannotSweepCurrency();
    /// @notice Error thrown when the tokens cannot be swept
    error CannotSweepTokens();
    /// @notice Error thrown when the auction has not graduated
    error NotGraduated();

    /// @notice Emitted when the tokens are swept
    /// @param tokensRecipient The address of the tokens recipient
    /// @param tokensAmount The amount of tokens swept
    event TokensSwept(address indexed tokensRecipient, uint256 tokensAmount);

    /// @notice Emitted when the currency is swept
    /// @param fundsRecipient The address of the funds recipient
    /// @param currencyAmount The amount of currency swept
    event CurrencySwept(address indexed fundsRecipient, uint256 currencyAmount);

    /// @notice The currency raised as of the last checkpoint in Q96 representation, scaled up by X7
    /// @dev Most use cases will want to use `currencyRaised()` instead
    /// @dev Any protocol fees set are NOT subtracted from the returned amount
    function currencyRaisedQ96X7() external view returns (ValueX7);

    /// @notice Get the currency raised at the last checkpointed block
    /// @dev Any protocol fees set are NOT subtracted from the returned amount
    /// @dev Relies on the latest checkpoint which may be out of date
    function currencyRaised() external view returns (uint256);

    /// @notice The sum of demand in ticks above the clearing price
    function sumCurrencyDemandAboveClearingQ96() external view returns (uint256);

    /// @notice The total currency raised as of the last checkpoint in Q96 representation, scaled up by X7
    function totalClearedQ96X7() external view returns (ValueX7);

    /// @notice The total tokens cleared as of the last checkpoint in uint256 representation
    /// @dev Loses precision from dividing into uint256 form
    function totalCleared() external view returns (uint256);

    /// @notice The remaining supply of tokens in Q96 representation, scaled up by X7
    /// @dev Relies on the latest checkpoint which may be out of date
    function remainingSupplyQ96X7() external view returns (ValueX7);

    /// @notice The remaining supply of tokens in uint256 representation
    /// @dev Loses precision from dividing into uint256 form
    /// @dev Relies on the latest checkpoint which may be out of date
    function remainingSupply() external view returns (uint256);
}
