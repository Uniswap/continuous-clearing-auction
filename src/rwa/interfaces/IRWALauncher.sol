// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IContinuousClearingAuction} from '../../interfaces/IContinuousClearingAuction.sol';

/// @notice Minter + budget weight for one pool side.
/// @dev `minter == address(0)` denotes an identity side: the pool token IS the funding currency and is
///      used directly without conversion (`token` must equal the funding currency).
struct SideConfig {
    address minter; // ITokenMinter, or address(0) for an identity passthrough
    address token; // the pool token this side produces (== currency for identity)
    uint16 budgetWeightBps; // share of the deposit routed to this side; side0 + side1 == 10_000
}

/// @notice A concentrated liquidity tranche seeded at build time.
struct TrancheConfig {
    uint24 rangeWidthBps; // half-width of the range around the init price (e.g. 5, 10, 50, 100)
    uint16 weightBps; // share of each side's minted balance allocated to this tranche; normalized at build
}

/// @notice Construction parameters for an RWA Launcher.
/// @dev The deposit notional `D` (in funding-currency base units) is passed separately as the constructor
///      `amount`; it equals the total `PositionShare` supply. The auction sells those shares for `currency`.
struct RWALauncherParameters {
    address currency; // funding currency the issuer deposits and bidders bid in
    SideConfig side0; // pool token0 minter + budget weight
    SideConfig side1; // pool token1 minter + budget weight
    address fundsRecipient; // issuer; receives auction proceeds
    address sharesRecipient; // issuer; receives unsold shares (co-LP) and residual dust
    uint64 startBlock; // auction (bidding) start
    uint64 endBlock; // auction end / finalize
    uint64 claimBlock; // winners may claim shares
    uint64 lpDuration; // blocks the position stays live after endBlock before it may be unwound
    uint256 tickSpacing; // Q96 granularity of the price-per-share (discount) axis
    uint256 maxDiscountBps; // worst discount the issuer will accept; sets the auction floor price
    uint128 requiredSharesSold; // graduation threshold (funding-currency base units)
    TrancheConfig[] tranches; // concentrated ranges seeded at build
    address validationHook; // optional CCA validation hook for gated participation
    bytes auctionStepsData; // CCA issuance schedule controlling share release over time
    address poolManager; // v4 PoolManager the position is created in
    int24 poolTickSpacing; // v4 pool tick spacing
    uint24 poolFee; // v4 pool LP fee (pips)
    address poolHooks; // v4 pool hooks (address(0) for none)
}

/// @notice The lifecycle stage of an RWA Launcher.
enum Stage {
    SETUP, // deployed; awaiting the issuer deposit
    BIDDING, // deposit received, auction live
    CLEARED, // auction ended & graduated, position built; awaiting the LP window
    ACTIVE, // market-making window in progress
    UNWOUND // liquidity withdrawn; redemption open
}

/// @title IRWALauncher
/// @notice Reverse-discount auction that sells fractional shares of an issuer-funded, multi-range v4 LP
///         position. Composes a {IContinuousClearingAuction} for bidding/clearing and owns settlement.
/// @custom:security-contact security@uniswap.org
interface IRWALauncher {
    error InvalidSideWeights(uint256 sum); // side0 + side1 budget weights must equal 10_000
    error InvalidIdentitySide(); // identity side token must equal the funding currency
    error InvalidTranches(); // tranche set empty or malformed
    error DepositAlreadyReceived();
    error InvalidDepositAmount(uint256 expected, uint256 received);
    error AuctionNotEnded();
    error NotGraduated();
    error AlreadyBuilt();
    error NotBuilt();
    error WindowNotElapsed(); // lpDuration has not passed since endBlock
    error AlreadyUnwound();
    error NotUnwound();
    error NothingToRedeem();

    event DepositReceived(uint256 amount);
    event PositionBuilt(uint256 initialPriceX96, uint256 amount0, uint256 amount1, uint256 proceeds);
    event Unwound(uint256 amount0, uint256 amount1);
    event Redeemed(address indexed owner, uint256 shares, uint256 amount0, uint256 amount1);

    /// @notice The composed auction handling bidding, clearing, exit, and share claims.
    function auction() external view returns (IContinuousClearingAuction);

    /// @notice The ERC20 position-share token sold by the auction and redeemed here.
    function shareToken() external view returns (address);

    /// @notice The current lifecycle stage.
    function stage() external view returns (Stage);

    /// @notice Notify the launcher that the issuer's deposit has been transferred in.
    /// @dev Push model: the issuer transfers `D` of the funding currency, then calls this. Mints the share
    ///      supply to the auction and starts bidding.
    function onTokensReceived() external;

    /// @notice Finalize the auction and build the position: route proceeds to the issuer, mint both pool
    ///         tokens from the deposit via the configured minters, and seed the multi-range v4 position.
    /// @dev Permissionless; callable once after `endBlock` when the auction has graduated.
    function build() external;

    /// @notice Withdraw all liquidity into the contract, opening redemption.
    /// @dev Permissionless; callable once after `endBlock + lpDuration`.
    function unwind() external;

    /// @notice Burn `shares` and receive the pro-rata share of the redemption pot.
    /// @param shares Amount of position shares to redeem
    /// @param toCurrency If true, both legs are converted back to the funding currency via the minters
    /// @return amount0 token0 (or currency) returned
    /// @return amount1 token1 (or currency) returned
    function redeem(uint256 shares, bool toCurrency) external returns (uint256 amount0, uint256 amount1);
}
