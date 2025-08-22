// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

/// @title ILBPStrategyBasic
/// @notice Interface for the LBPStrategyBasic contract
interface ISubscriber {
    /// @notice Emitted when the initial price is set
    event InitialPriceSet(uint256 priceX192, uint256 tokenAmount, uint256 currencyAmount);

    /// @notice Error thrown when caller is not the auction contract
    error OnlyAuctionCanSetPrice(address auction, address caller);

    /// @notice Error thrown when the currency amount transferred is invalid
    error InvalidCurrencyAmount(uint256 expected, uint256 received);

    /// @notice Error thrown when ETH is sent to the contract but the configured currency is not ETH (e.g. an ERC20 token)
    error NonETHCurrencyCannotReceiveETH(address currency);

    /// @notice Error thrown when the price is invalid
    error InvalidPrice(uint256 price);

    /// @notice Error thrown when the liquidity is invalid
    error InvalidLiquidity(uint128 maxLiquidityPerTick, uint128 liquidity);

    /// @notice Error thrown when the token amount is invalid
    error InvalidTokenAmount(uint128 tokenAmount, uint128 reserveSupply);

    /// @notice Sets the initial price of the pool based on the auction results and transfers the currency to the contract
    /// @param priceX192 The price of the pool in 192-bit fixed point format (2 ** 192 * price)
    /// @param tokenAmount The amount of tokens needed for that price
    /// @param currencyAmount The amount of currency needed for that price and transferred to the contract
    function setInitialPrice(uint256 priceX192, uint128 tokenAmount, uint128 currencyAmount) external payable;
}
