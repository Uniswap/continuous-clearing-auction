// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface ITokenCurrencyStorage {
    /// @notice Error thrown when the total supply is zero
    error TotalSupplyIsZero();
    /// @notice Error thrown when the funds recipient is the zero address
    error FundsRecipientIsZero();
}
