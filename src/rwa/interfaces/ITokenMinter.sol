// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @title ITokenMinter
/// @notice Converts an RWA Launcher's funding currency into one of the two pool tokens (and back, for
///         redemption) at a known rate. One minter is configured per pool side. The two minters' prices
///         derive the pool's initialization price; the funding currency is never trusted for price.
/// @dev An "identity" side (a pool token that IS the funding currency) is represented by a zero minter
///      address in the launcher config and never calls this interface.
/// @custom:security-contact security@uniswap.org
interface ITokenMinter {
    /// @notice The funding currency this minter consumes
    function currency() external view returns (address);

    /// @notice The pool token this minter produces
    function token() external view returns (address);

    /// @notice Convert `currencyAmount` of `currency` into `token` at the current rate.
    /// @dev The caller MUST have transferred / approved `currencyAmount` of `currency` per the minter's
    ///      pull model. Mints to `msg.sender`.
    /// @param currencyAmount Amount of funding currency to convert
    /// @return tokenAmount Amount of `token` minted to the caller
    function mint(uint256 currencyAmount) external returns (uint256 tokenAmount);

    /// @notice Convert `tokenAmount` of `token` back into `currency` at the current rate.
    /// @dev Used at redemption when a holder opts to receive the funding currency. Returns to `msg.sender`.
    /// @param tokenAmount Amount of `token` to convert
    /// @return currencyAmount Amount of funding currency returned to the caller
    function redeem(uint256 tokenAmount) external returns (uint256 currencyAmount);

    /// @notice Price of one whole `token` denominated in `currency`, in Q96 fixed-point form.
    /// @dev Used to derive the pool initialization price as the ratio of the two sides' prices.
    function priceQ96() external view returns (uint256);
}
