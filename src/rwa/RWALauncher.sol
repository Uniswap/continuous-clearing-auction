// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {AuctionParameters, IContinuousClearingAuction} from '../interfaces/IContinuousClearingAuction.sol';
import {IContinuousClearingAuctionFactory} from '../interfaces/IContinuousClearingAuctionFactory.sol';
import {FixedPoint96} from '../libraries/FixedPoint96.sol';
import {PositionShare} from './PositionShare.sol';
import {
    IRWALauncher, RWALauncherParameters, SideConfig, TrancheConfig, Stage
} from './interfaces/IRWALauncher.sol';
import {ITokenMinter} from './interfaces/ITokenMinter.sol';
import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {IERC20Metadata} from '@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol';
import {IDistributor} from 'liquidity-launcher/src/interfaces/IDistributor.sol';
import {FixedPointMathLib} from 'solady/utils/FixedPointMathLib.sol';
import {ReentrancyGuardTransient} from 'solady/utils/ReentrancyGuardTransient.sol';
import {SafeTransferLib} from 'solady/utils/SafeTransferLib.sol';
import {ActionConstants} from 'v4-periphery/src/libraries/ActionConstants.sol';
import {LiquidityAmounts} from 'v4-periphery/src/libraries/LiquidityAmounts.sol';
import {IPoolManager} from 'v4-periphery/lib/v4-core/src/interfaces/IPoolManager.sol';
import {IUnlockCallback} from 'v4-periphery/lib/v4-core/src/interfaces/callback/IUnlockCallback.sol';
import {IHooks} from 'v4-periphery/lib/v4-core/src/interfaces/IHooks.sol';
import {BalanceDelta} from 'v4-periphery/lib/v4-core/src/types/BalanceDelta.sol';
import {Currency, CurrencyLibrary} from 'v4-periphery/lib/v4-core/src/types/Currency.sol';
import {PoolId, PoolIdLibrary} from 'v4-periphery/lib/v4-core/src/types/PoolId.sol';
import {PoolKey} from 'v4-periphery/lib/v4-core/src/types/PoolKey.sol';
import {ModifyLiquidityParams} from 'v4-periphery/lib/v4-core/src/types/PoolOperation.sol';
import {StateLibrary} from 'v4-periphery/lib/v4-core/src/libraries/StateLibrary.sol';
import {TickMath} from 'v4-periphery/lib/v4-core/src/libraries/TickMath.sol';

/// @title RWALauncher
/// @notice Reverse-discount auction that sells fractional shares of an issuer-funded, multi-range Uniswap v4
///         LP position. Composes a {ContinuousClearingAuction} for bidding/clearing (the discount axis is the
///         CCA price axis, `p = ONE_Q96 * (1 - discount/1e4)`) and owns settlement: minting both pool tokens
///         from the deposit via per-side minters, seeding the multi-range position, and the unwind/redeem
///         lifecycle.
/// @dev Decimal convention: minter `priceQ96` and share/currency amounts are interpreted in token BASE units
///      (the share token's decimals match the funding currency, so a full-NAV share price is exactly ONE_Q96).
///      Minter implementors MUST price one base unit of `token` in base units of `currency`, Q96.
/// @custom:security-contact security@uniswap.org
contract RWALauncher is IRWALauncher, IUnlockCallback, ReentrancyGuardTransient {
    using CurrencyLibrary for Currency;
    using PoolIdLibrary for PoolKey;
    using StateLibrary for IPoolManager;
    using SafeTransferLib for address;

    uint256 internal constant BPS = 10_000;
    uint256 internal constant ONE_Q96 = FixedPoint96.Q96;

    /// @inheritdoc IRWALauncher
    IContinuousClearingAuction public immutable auction;
    /// @notice The ERC20 position-share token (typed)
    PositionShare public immutable SHARE;
    /// @notice The v4 PoolManager the position lives in
    IPoolManager public immutable POOL_MANAGER;

    Currency internal immutable CURRENCY;
    uint128 public immutable DEPOSIT;
    uint64 public immutable END_BLOCK;
    uint64 public immutable LP_DURATION;
    address public immutable ISSUER_FUNDS;
    address public immutable ISSUER_SHARES;

    address internal immutable SIDE0_MINTER;
    address internal immutable SIDE0_TOKEN;
    uint16 internal immutable SIDE0_WEIGHT;
    address internal immutable SIDE1_MINTER;
    address internal immutable SIDE1_TOKEN;
    uint16 internal immutable SIDE1_WEIGHT;

    uint24 internal immutable POOL_FEE;
    int24 internal immutable POOL_TICK_SPACING;
    address internal immutable POOL_HOOKS;

    /// @notice Tranche definitions (range width + weight) seeded at build
    TrancheConfig[] internal _tranches;
    uint256 internal _sumTrancheWeight;

    /// @notice A seeded position's range + salt, recorded at build for unwind
    struct SeededPosition {
        int24 tickLower;
        int24 tickUpper;
        bytes32 salt;
    }

    SeededPosition[] internal _positions;
    PoolKey internal _poolKey;

    Stage internal _stage;
    bool internal _built;
    bool internal _unwound;
    bool internal _depositReceived;

    /// @notice Auction proceeds routed to the issuer at build (funding currency)
    uint256 public proceeds;
    /// @notice Redemption pot (pool token0/token1 amounts) after unwind
    uint256 public pot0;
    uint256 public pot1;
    /// @notice Share supply backing the redemption pot, decremented as holders redeem
    uint256 internal _sharesOutstanding;

    enum CallbackAction {
        SEED,
        WITHDRAW
    }

    constructor(uint128 _deposit, RWALauncherParameters memory p, IContinuousClearingAuctionFactory ccaFactory) {
        uint256 weightSum = uint256(p.side0.budgetWeightBps) + p.side1.budgetWeightBps;
        if (weightSum != BPS) revert InvalidSideWeights(weightSum);
        if (p.side0.minter == address(0) && p.side0.token != p.currency) revert InvalidIdentitySide();
        if (p.side1.minter == address(0) && p.side1.token != p.currency) revert InvalidIdentitySide();
        if (p.tranches.length == 0) revert InvalidTranches();

        DEPOSIT = _deposit;
        CURRENCY = Currency.wrap(p.currency);
        END_BLOCK = p.endBlock;
        LP_DURATION = p.lpDuration;
        ISSUER_FUNDS = p.fundsRecipient;
        ISSUER_SHARES = p.sharesRecipient;
        POOL_MANAGER = IPoolManager(p.poolManager);

        SIDE0_MINTER = p.side0.minter;
        SIDE0_TOKEN = p.side0.token;
        SIDE0_WEIGHT = p.side0.budgetWeightBps;
        SIDE1_MINTER = p.side1.minter;
        SIDE1_TOKEN = p.side1.token;
        SIDE1_WEIGHT = p.side1.budgetWeightBps;

        POOL_FEE = p.poolFee;
        POOL_TICK_SPACING = p.poolTickSpacing;
        POOL_HOOKS = p.poolHooks;

        uint256 sumW;
        for (uint256 i; i < p.tranches.length; ++i) {
            _tranches.push(p.tranches[i]);
            sumW += p.tranches[i].weightBps;
        }
        _sumTrancheWeight = sumW;

        // Share token decimals match the funding currency so a full-NAV share price is exactly ONE_Q96.
        SHARE = new PositionShare('RWA Launcher Position Share', 'RWA-LP', IERC20Metadata(p.currency).decimals());

        // Map the discount axis onto the CCA price axis: floor = ONE_Q96 * (1 - maxDiscount/1e4), rounded
        // down to a tick boundary (the CCA requires the floor to be a multiple of tickSpacing).
        uint256 floorPrice = (ONE_Q96 * (BPS - p.maxDiscountBps)) / BPS;
        floorPrice = (floorPrice / p.tickSpacing) * p.tickSpacing;
        // Graduate when currency raised >= requiredSharesSold valued at the floor price.
        uint128 requiredCurrencyRaised = uint128((uint256(p.requiredSharesSold) * (BPS - p.maxDiscountBps)) / BPS);

        AuctionParameters memory ap = AuctionParameters({
            currency: p.currency,
            tokensRecipient: ActionConstants.MSG_SENDER, // resolves to this launcher
            fundsRecipient: ActionConstants.MSG_SENDER, // resolves to this launcher
            startBlock: p.startBlock,
            endBlock: p.endBlock,
            claimBlock: p.claimBlock,
            tickSpacing: p.tickSpacing,
            validationHook: p.validationHook,
            floorPrice: floorPrice,
            requiredCurrencyRaised: requiredCurrencyRaised,
            auctionStepsData: p.auctionStepsData
        });

        IDistributor dist = ccaFactory.create(address(SHARE), _deposit, abi.encode(ap), bytes32(0));
        auction = IContinuousClearingAuction(address(dist));
        _stage = Stage.SETUP;
    }

    /// @inheritdoc IRWALauncher
    function shareToken() external view returns (address) {
        return address(SHARE);
    }

    /// @inheritdoc IRWALauncher
    function stage() external view returns (Stage) {
        return _stage;
    }

    /// @inheritdoc IRWALauncher
    /// @dev Push model: the issuer transfers `DEPOSIT` of the funding currency to this contract, then calls
    ///      this. Mints the share supply to the auction and opens bidding.
    function onTokensReceived() external nonReentrant {
        if (_depositReceived) revert DepositAlreadyReceived();
        uint256 bal = CURRENCY.balanceOfSelf();
        if (bal < DEPOSIT) revert InvalidDepositAmount(DEPOSIT, bal);
        _depositReceived = true;

        SHARE.mint(address(auction), DEPOSIT);
        auction.onTokensReceived();

        _stage = Stage.BIDDING;
        emit DepositReceived(DEPOSIT);
    }

    /// @inheritdoc IRWALauncher
    function build() external nonReentrant {
        if (_built) revert AlreadyBuilt();
        // Finalize the auction at the end block.
        auction.checkpoint();
        if (auction.endBlock() >= _blockNumber()) revert AuctionNotEnded();
        if (!auction.isGraduated()) revert NotGraduated();
        _built = true;

        // Route proceeds to the issuer. The launcher is the CCA funds recipient, so its balance after the
        // sweep is the issuer deposit plus the swept proceeds; the deposit is retained to mint pool tokens.
        auction.sweepCurrency();
        uint256 bal = CURRENCY.balanceOfSelf();
        uint256 proceedsAmt = bal > DEPOSIT ? bal - DEPOSIT : 0;
        proceeds = proceedsAmt;
        if (proceedsAmt > 0) Currency.unwrap(CURRENCY).safeTransfer(ISSUER_FUNDS, proceedsAmt);

        // Forward any unsold shares to the issuer (co-LP stake).
        auction.sweepUnsoldTokens();
        uint256 unsold = SHARE.balanceOf(address(this));
        if (unsold > 0) SHARE.transfer(ISSUER_SHARES, unsold);

        // Mint both pool tokens from the deposit via the configured minters.
        uint256 budget0 = (uint256(DEPOSIT) * SIDE0_WEIGHT) / BPS;
        uint256 budget1 = uint256(DEPOSIT) - budget0;
        uint256 minted0 = _mintSide(SIDE0_MINTER, budget0);
        uint256 minted1 = _mintSide(SIDE1_MINTER, budget1);

        uint256 price0 = SIDE0_MINTER == address(0) ? ONE_Q96 : ITokenMinter(SIDE0_MINTER).priceQ96();
        uint256 price1 = SIDE1_MINTER == address(0) ? ONE_Q96 : ITokenMinter(SIDE1_MINTER).priceQ96();

        // Sort tokens into v4 pool currency order and align amounts/prices accordingly.
        bool zeroIsSide0 = SIDE0_TOKEN < SIDE1_TOKEN;
        (Currency c0, Currency c1) = zeroIsSide0
            ? (Currency.wrap(SIDE0_TOKEN), Currency.wrap(SIDE1_TOKEN))
            : (Currency.wrap(SIDE1_TOKEN), Currency.wrap(SIDE0_TOKEN));
        (uint256 amt0, uint256 amt1) = zeroIsSide0 ? (minted0, minted1) : (minted1, minted0);
        (uint256 pc0, uint256 pc1) = zeroIsSide0 ? (price0, price1) : (price1, price0);

        // Pool price (currency1 per currency0) = price(c0-token in funding currency) / price(c1-token).
        uint256 ratioX96 = FixedPointMathLib.fullMulDiv(pc0, ONE_Q96, pc1);
        uint160 sqrtPriceX96 = uint160(FixedPointMathLib.sqrt(FixedPointMathLib.fullMulDiv(ratioX96, ONE_Q96, 1)));

        _poolKey = PoolKey({
            currency0: c0,
            currency1: c1,
            fee: POOL_FEE,
            tickSpacing: POOL_TICK_SPACING,
            hooks: IHooks(POOL_HOOKS)
        });
        POOL_MANAGER.initialize(_poolKey, sqrtPriceX96);

        POOL_MANAGER.unlock(abi.encode(CallbackAction.SEED, sqrtPriceX96, amt0, amt1));

        // Return residual dust (whichever side was over-budgeted) to the issuer.
        uint256 dust0 = c0.balanceOfSelf();
        uint256 dust1 = c1.balanceOfSelf();
        if (dust0 > 0) Currency.unwrap(c0).safeTransfer(ISSUER_SHARES, dust0);
        if (dust1 > 0) Currency.unwrap(c1).safeTransfer(ISSUER_SHARES, dust1);

        _stage = Stage.ACTIVE;
        emit PositionBuilt(sqrtPriceX96, amt0, amt1, proceedsAmt);
    }

    /// @inheritdoc IRWALauncher
    function unwind() external nonReentrant {
        if (!_built) revert NotBuilt();
        if (_unwound) revert AlreadyUnwound();
        if (_blockNumber() < uint256(END_BLOCK) + LP_DURATION) revert WindowNotElapsed();
        _unwound = true;

        POOL_MANAGER.unlock(abi.encode(CallbackAction.WITHDRAW, uint160(0), uint256(0), uint256(0)));

        pot0 = _poolKey.currency0.balanceOfSelf();
        pot1 = _poolKey.currency1.balanceOfSelf();
        _sharesOutstanding = SHARE.totalSupply();

        _stage = Stage.UNWOUND;
        emit Unwound(pot0, pot1);
    }

    /// @inheritdoc IRWALauncher
    function redeem(uint256 shares, bool toCurrency)
        external
        nonReentrant
        returns (uint256 amount0, uint256 amount1)
    {
        if (!_unwound) revert NotUnwound();
        if (shares == 0 || _sharesOutstanding == 0) revert NothingToRedeem();

        amount0 = (pot0 * shares) / _sharesOutstanding;
        amount1 = (pot1 * shares) / _sharesOutstanding;

        pot0 -= amount0;
        pot1 -= amount1;
        _sharesOutstanding -= shares;

        SHARE.burn(msg.sender, shares); // burns the caller's own shares

        _payout(_poolKey.currency0, amount0, toCurrency);
        _payout(_poolKey.currency1, amount1, toCurrency);

        emit Redeemed(msg.sender, shares, amount0, amount1);
    }

    /// @inheritdoc IUnlockCallback
    function unlockCallback(bytes calldata data) external returns (bytes memory) {
        if (msg.sender != address(POOL_MANAGER)) revert NotBuilt();
        (CallbackAction action, uint160 sqrtPriceX96, uint256 amt0, uint256 amt1) =
            abi.decode(data, (CallbackAction, uint160, uint256, uint256));

        if (action == CallbackAction.SEED) {
            _seed(sqrtPriceX96, amt0, amt1);
        } else {
            _withdraw();
        }
        return '';
    }

    // -- internal --------------------------------------------------------------------------------------------

    function _seed(uint160 sqrtPriceX96, uint256 amt0, uint256 amt1) internal {
        int24 spacing = POOL_TICK_SPACING;
        int24 center = _snap(TickMath.getTickAtSqrtPrice(sqrtPriceX96));
        int256 owed0;
        int256 owed1;
        uint256 sumW = _sumTrancheWeight;

        for (uint256 i; i < _tranches.length; ++i) {
            TrancheConfig memory t = _tranches[i];
            // A range half-width of `rangeWidthBps` bps is ~`rangeWidthBps` ticks (1.0001^1 ≈ 1bp).
            int24 off = _snapWidth(int24(uint24(t.rangeWidthBps)), spacing);
            int24 lower = center - off;
            int24 upper = center + off;
            if (lower < TickMath.MIN_TICK) lower = _snap(TickMath.MIN_TICK);
            if (upper > TickMath.MAX_TICK) upper = _snap(TickMath.MAX_TICK);

            uint256 a0 = (amt0 * t.weightBps) / sumW;
            uint256 a1 = (amt1 * t.weightBps) / sumW;
            uint128 liquidity = LiquidityAmounts.getLiquidityForAmounts(
                sqrtPriceX96, TickMath.getSqrtPriceAtTick(lower), TickMath.getSqrtPriceAtTick(upper), a0, a1
            );
            if (liquidity == 0) continue;

            bytes32 salt = bytes32(i);
            (BalanceDelta delta,) = POOL_MANAGER.modifyLiquidity(
                _poolKey,
                ModifyLiquidityParams({
                    tickLower: lower,
                    tickUpper: upper,
                    liquidityDelta: int256(uint256(liquidity)),
                    salt: salt
                }),
                ''
            );
            owed0 += int256(delta.amount0());
            owed1 += int256(delta.amount1());
            _positions.push(SeededPosition({tickLower: lower, tickUpper: upper, salt: salt}));
        }

        if (owed0 < 0) _settle(_poolKey.currency0, uint256(-owed0));
        if (owed1 < 0) _settle(_poolKey.currency1, uint256(-owed1));
    }

    function _withdraw() internal {
        PoolId poolId = _poolKey.toId();
        int256 owed0;
        int256 owed1;

        for (uint256 i; i < _positions.length; ++i) {
            SeededPosition memory pos = _positions[i];
            uint128 liquidity =
                POOL_MANAGER.getPositionLiquidity(poolId, _positionKey(pos.tickLower, pos.tickUpper, pos.salt));
            if (liquidity == 0) continue;
            (BalanceDelta delta,) = POOL_MANAGER.modifyLiquidity(
                _poolKey,
                ModifyLiquidityParams({
                    tickLower: pos.tickLower,
                    tickUpper: pos.tickUpper,
                    liquidityDelta: -int256(uint256(liquidity)),
                    salt: pos.salt
                }),
                ''
            );
            owed0 += int256(delta.amount0());
            owed1 += int256(delta.amount1());
        }

        if (owed0 > 0) POOL_MANAGER.take(_poolKey.currency0, address(this), uint256(owed0));
        if (owed1 > 0) POOL_MANAGER.take(_poolKey.currency1, address(this), uint256(owed1));
    }

    /// @dev Mint a pool token from `budget` of funding currency, or pass currency through for an identity side.
    function _mintSide(address minter, uint256 budget) internal returns (uint256) {
        if (minter == address(0)) return budget; // identity: token IS the funding currency
        Currency.unwrap(CURRENCY).safeApproveWithRetry(minter, budget);
        return ITokenMinter(minter).mint(budget);
    }

    /// @dev Pay `amount` of `currency` to the caller, optionally converting back to the funding currency.
    function _payout(Currency currency, uint256 amount, bool toCurrency) internal {
        if (amount == 0) return;
        address token = Currency.unwrap(currency);
        address minter = _minterFor(token);
        if (toCurrency && minter != address(0)) {
            token.safeApproveWithRetry(minter, amount);
            uint256 out = ITokenMinter(minter).redeem(amount);
            Currency.unwrap(CURRENCY).safeTransfer(msg.sender, out);
        } else {
            token.safeTransfer(msg.sender, amount);
        }
    }

    /// @dev The minter that produced `token`, or address(0) for an identity side (or unknown).
    function _minterFor(address token) internal view returns (address) {
        if (token == SIDE0_TOKEN) return SIDE0_MINTER;
        if (token == SIDE1_TOKEN) return SIDE1_MINTER;
        return address(0);
    }

    /// @dev Pay a v4 negative delta: sync, transfer the owed token to the manager, settle.
    function _settle(Currency currency, uint256 amount) internal {
        POOL_MANAGER.sync(currency);
        currency.transfer(address(POOL_MANAGER), amount);
        POOL_MANAGER.settle();
    }

    function _positionKey(int24 tickLower, int24 tickUpper, bytes32 salt) internal view returns (bytes32) {
        return keccak256(abi.encodePacked(address(this), tickLower, tickUpper, salt));
    }

    function _snap(int24 tick) internal view returns (int24) {
        int24 s = POOL_TICK_SPACING;
        return (tick / s) * s;
    }

    function _snapWidth(int24 width, int24 spacing) internal pure returns (int24) {
        int24 w = (width / spacing) * spacing;
        return w < spacing ? spacing : w;
    }

    function _blockNumber() internal view returns (uint256) {
        return block.number;
    }
}
