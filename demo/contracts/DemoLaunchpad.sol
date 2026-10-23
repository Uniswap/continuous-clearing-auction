// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {FixedPoint96} from '../../src/libraries/FixedPoint96.sol';
import {PositionShare} from '../../src/rwa/PositionShare.sol';
import {ITokenMinter} from '../../src/rwa/interfaces/ITokenMinter.sol';
import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {IERC20Metadata} from '@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol';
import {FixedPointMathLib} from 'solady/utils/FixedPointMathLib.sol';
import {ReentrancyGuardTransient} from 'solady/utils/ReentrancyGuardTransient.sol';
import {SafeTransferLib} from 'solady/utils/SafeTransferLib.sol';
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

/// @title DemoLaunchpad
/// @notice DEMO-ONLY variant of the RWA Launcher with a fully permissionless lifecycle: anyone can `end()`
///         the auction (clear + build the multi-range v4 position) and anyone can `unwind()` to end the
///         lockup (withdraw liquidity); each holder then `redeem()`s their pro-rata tokens. Unlike the
///         production launcher (a time-weighted CCA that finalizes only at its end block), this escrows bids
///         directly and clears discretely so the whole flow can be driven on demand. Not for production.
/// @custom:security-contact security@uniswap.org
contract DemoLaunchpad is IUnlockCallback, ReentrancyGuardTransient {
    using CurrencyLibrary for Currency;
    using PoolIdLibrary for PoolKey;
    using StateLibrary for IPoolManager;
    using SafeTransferLib for address;

    uint256 internal constant BPS = 10_000;
    uint256 internal constant ONE_Q96 = FixedPoint96.Q96;

    struct Bid {
        address bidder;
        uint128 amount;
        uint16 discount;
    }

    struct Pos {
        int24 tickLower;
        int24 tickUpper;
        bytes32 salt;
    }

    enum Action {
        SEED,
        WITHDRAW
    }

    PositionShare public immutable SHARE;
    IPoolManager public immutable POOL_MANAGER;
    Currency internal immutable CURRENCY;
    uint128 public immutable DEPOSIT;
    uint16 public immutable MAX_DISCOUNT_BPS;
    address public immutable ISSUER;

    address internal immutable SIDE0_MINTER;
    address internal immutable SIDE0_TOKEN;
    address internal immutable SIDE1_MINTER;
    address internal immutable SIDE1_TOKEN;
    int24 internal immutable POOL_TICK_SPACING;
    uint24 internal immutable POOL_FEE;

    Bid[] public bids;
    Pos[] internal _positions;
    PoolKey internal _poolKey;

    bool public started;
    bool public ended;
    bool public unwound;
    uint256 public proceeds;
    uint256 public clearingDiscountFinal;
    uint256 public pot0;
    uint256 public pot1;
    uint256 public sharesOutstanding;

    // Half-widths in v4 ticks (1 tick ≈ 1bp). Spread across multiples of the pool tick spacing so the tranches
    // render as distinct nested bands (≈ ±3% / ±13% / ±62% / ±230%) rather than collapsing into one position.
    int24[4] internal WIDTHS = [int24(300), 1200, 4800, 12000];
    uint16[4] internal WEIGHTS = [uint16(1_000), 2_000, 3_000, 4_000];

    error AlreadyStarted();
    error NotStarted();
    error AlreadyEnded();
    error NotEnded();
    error AlreadyUnwound();
    error NotUnwound();
    error DepositNotFunded();
    error DiscountTooHigh();
    error ZeroAmount();
    error NothingToRedeem();

    event Started(uint128 deposit);
    event BidPlaced(address indexed bidder, uint128 amount, uint16 discount);
    event Ended(uint16 clearingDiscount, uint256 proceeds, uint256 amount0, uint256 amount1);
    event Unwound(uint256 amount0, uint256 amount1);
    event Redeemed(address indexed owner, uint256 shares, uint256 amount0, uint256 amount1);

    constructor(
        address issuer,
        address currency,
        uint128 deposit,
        uint16 maxDiscountBps,
        address side0Minter,
        address side0Token,
        address side1Minter,
        address side1Token,
        address poolManager,
        int24 poolTickSpacing,
        uint24 poolFee
    ) {
        ISSUER = issuer;
        CURRENCY = Currency.wrap(currency);
        DEPOSIT = deposit;
        MAX_DISCOUNT_BPS = maxDiscountBps;
        SIDE0_MINTER = side0Minter;
        SIDE0_TOKEN = side0Token;
        SIDE1_MINTER = side1Minter;
        SIDE1_TOKEN = side1Token;
        POOL_MANAGER = IPoolManager(poolManager);
        POOL_TICK_SPACING = poolTickSpacing;
        POOL_FEE = poolFee;
        SHARE = new PositionShare('RWA Launcher Position Share', 'RWA-LP', IERC20Metadata(currency).decimals());
    }

    function start() external {
        if (started) revert AlreadyStarted();
        if (CURRENCY.balanceOfSelf() < DEPOSIT) revert DepositNotFunded();
        started = true;
        emit Started(DEPOSIT);
    }

    function bid(uint128 amount, uint16 discount) external nonReentrant {
        if (!started) revert NotStarted();
        if (ended) revert AlreadyEnded();
        if (amount == 0) revert ZeroAmount();
        if (discount > MAX_DISCOUNT_BPS) revert DiscountTooHigh();
        Currency.unwrap(CURRENCY).safeTransferFrom(msg.sender, address(this), amount);
        bids.push(Bid({bidder: msg.sender, amount: amount, discount: discount}));
        emit BidPlaced(msg.sender, amount, discount);
    }

    function clearingDiscount() public view returns (uint16) {
        (uint16 d,,) = _clearing();
        return d;
    }

    function bidCount() external view returns (uint256) {
        return bids.length;
    }

    /// @notice The v4 poolId of the pool this launchpad will build (deterministic from its config).
    function poolId() external view returns (bytes32) {
        bool z = SIDE0_TOKEN < SIDE1_TOKEN;
        (Currency c0, Currency c1) = z
            ? (Currency.wrap(SIDE0_TOKEN), Currency.wrap(SIDE1_TOKEN))
            : (Currency.wrap(SIDE1_TOKEN), Currency.wrap(SIDE0_TOKEN));
        return PoolId.unwrap(
            PoolKey({currency0: c0, currency1: c1, fee: POOL_FEE, tickSpacing: POOL_TICK_SPACING, hooks: IHooks(address(0))}).toId()
        );
    }

    /// @notice Permissionlessly end the auction: clear, refund, route proceeds to the issuer, mint both pool
    ///         tokens from the deposit, and seed the multi-range v4 position. Callable by anyone, any time.
    function end() external nonReentrant {
        if (!started) revert NotStarted();
        if (ended) revert AlreadyEnded();
        ended = true;

        (uint16 dStar, uint256 cumBefore, uint256 totalDemand) = _clearing();
        clearingDiscountFinal = dStar;
        uint256 D = DEPOSIT;
        uint256 oneMinusD = BPS - dStar;
        uint256 remaining = D > cumBefore ? D - cumBefore : 0;

        uint256 atMarginal;
        if (totalDemand > D) {
            for (uint256 i; i < bids.length; ++i) {
                if (bids[i].discount == dStar) atMarginal += bids[i].amount;
            }
        }

        uint256 _proceeds;
        uint256 totalFilled;
        for (uint256 i; i < bids.length; ++i) {
            Bid memory b = bids[i];
            uint256 filled;
            if (totalDemand <= D || b.discount < dStar) {
                filled = b.amount;
            } else if (b.discount == dStar) {
                filled = atMarginal > 0 ? (uint256(b.amount) * remaining) / atMarginal : 0;
            }
            uint256 pay = (filled * oneMinusD) / BPS;
            _proceeds += pay;
            totalFilled += filled;
            uint256 refund = uint256(b.amount) - pay;
            if (refund > 0) Currency.unwrap(CURRENCY).safeTransfer(b.bidder, refund);
            if (filled > 0) SHARE.mint(b.bidder, filled);
        }
        // Unsold shares go to the issuer (co-LP), so total shares == the position notional D.
        if (D > totalFilled) SHARE.mint(ISSUER, D - totalFilled);
        proceeds = _proceeds;
        if (_proceeds > 0) Currency.unwrap(CURRENCY).safeTransfer(ISSUER, _proceeds);

        uint256 budget0 = D / 2;
        uint256 minted0 = _mintSide(SIDE0_MINTER, budget0);
        uint256 minted1 = _mintSide(SIDE1_MINTER, D - budget0);
        uint256 price0 = SIDE0_MINTER == address(0) ? ONE_Q96 : ITokenMinter(SIDE0_MINTER).priceQ96();
        uint256 price1 = SIDE1_MINTER == address(0) ? ONE_Q96 : ITokenMinter(SIDE1_MINTER).priceQ96();

        bool zeroIsSide0 = SIDE0_TOKEN < SIDE1_TOKEN;
        (Currency c0, Currency c1) = zeroIsSide0
            ? (Currency.wrap(SIDE0_TOKEN), Currency.wrap(SIDE1_TOKEN))
            : (Currency.wrap(SIDE1_TOKEN), Currency.wrap(SIDE0_TOKEN));
        (uint256 amt0, uint256 amt1) = zeroIsSide0 ? (minted0, minted1) : (minted1, minted0);
        (uint256 pc0, uint256 pc1) = zeroIsSide0 ? (price0, price1) : (price1, price0);

        uint256 ratioX96 = FixedPointMathLib.fullMulDiv(pc0, ONE_Q96, pc1);
        uint160 sqrtPriceX96 = uint160(FixedPointMathLib.sqrt(FixedPointMathLib.fullMulDiv(ratioX96, ONE_Q96, 1)));

        _poolKey = PoolKey({
            currency0: c0,
            currency1: c1,
            fee: POOL_FEE,
            tickSpacing: POOL_TICK_SPACING,
            hooks: IHooks(address(0))
        });
        POOL_MANAGER.initialize(_poolKey, sqrtPriceX96);
        POOL_MANAGER.unlock(abi.encode(Action.SEED, sqrtPriceX96, amt0, amt1));

        uint256 dust0 = c0.balanceOfSelf();
        uint256 dust1 = c1.balanceOfSelf();
        if (dust0 > 0) Currency.unwrap(c0).safeTransfer(ISSUER, dust0);
        if (dust1 > 0) Currency.unwrap(c1).safeTransfer(ISSUER, dust1);

        emit Ended(dStar, _proceeds, amt0, amt1);
    }

    /// @notice Permissionlessly end the lockup: withdraw all liquidity back into the contract for redemption.
    ///         Callable by anyone, any time after the position is built.
    function unwind() external nonReentrant {
        if (!ended) revert NotEnded();
        if (unwound) revert AlreadyUnwound();
        unwound = true;
        POOL_MANAGER.unlock(abi.encode(Action.WITHDRAW, uint160(0), uint256(0), uint256(0)));
        pot0 = _poolKey.currency0.balanceOfSelf();
        pot1 = _poolKey.currency1.balanceOfSelf();
        sharesOutstanding = SHARE.totalSupply();
        emit Unwound(pot0, pot1);
    }

    /// @notice Burn `shares` and receive the pro-rata share of the withdrawn pot (token0 + token1).
    function redeem(uint256 shares) external nonReentrant returns (uint256 amount0, uint256 amount1) {
        if (!unwound) revert NotUnwound();
        if (shares == 0 || sharesOutstanding == 0) revert NothingToRedeem();
        amount0 = (pot0 * shares) / sharesOutstanding;
        amount1 = (pot1 * shares) / sharesOutstanding;
        pot0 -= amount0;
        pot1 -= amount1;
        sharesOutstanding -= shares;
        SHARE.burn(msg.sender, shares);
        if (amount0 > 0) Currency.unwrap(_poolKey.currency0).safeTransfer(msg.sender, amount0);
        if (amount1 > 0) Currency.unwrap(_poolKey.currency1).safeTransfer(msg.sender, amount1);
        emit Redeemed(msg.sender, shares, amount0, amount1);
    }

    /// @inheritdoc IUnlockCallback
    function unlockCallback(bytes calldata data) external returns (bytes memory) {
        if (msg.sender != address(POOL_MANAGER)) revert NotStarted();
        (Action action, uint160 sqrtPriceX96, uint256 amt0, uint256 amt1) =
            abi.decode(data, (Action, uint160, uint256, uint256));
        if (action == Action.SEED) {
            _seed(sqrtPriceX96, amt0, amt1);
        } else {
            _withdraw();
        }
        return '';
    }

    // -- internal --------------------------------------------------------------------------------------------

    function _clearing() internal view returns (uint16 dStar, uint256 cumBefore, uint256 totalDemand) {
        uint16 max = MAX_DISCOUNT_BPS;
        uint256 D = DEPOSIT;
        uint256[] memory perLevel = new uint256[](uint256(max) + 1);
        for (uint256 i; i < bids.length; ++i) {
            perLevel[bids[i].discount] += bids[i].amount;
            totalDemand += bids[i].amount;
        }
        if (totalDemand <= D) return (max, totalDemand, totalDemand);
        uint256 cum;
        for (uint16 L = 0; L <= max; ++L) {
            uint256 prev = cum;
            cum += perLevel[L];
            if (cum >= D) return (L, prev, totalDemand);
        }
        return (max, cum, totalDemand);
    }

    function _seed(uint160 sqrtPriceX96, uint256 amt0, uint256 amt1) internal {
        int24 spacing = POOL_TICK_SPACING;
        int24 center = (TickMath.getTickAtSqrtPrice(sqrtPriceX96) / spacing) * spacing;
        int256 owed0;
        int256 owed1;
        for (uint256 i; i < 4; ++i) {
            int24 off = (WIDTHS[i] / spacing) * spacing;
            if (off < spacing) off = spacing;
            int24 lower = center - off;
            int24 upper = center + off;
            if (lower < TickMath.MIN_TICK) lower = (TickMath.MIN_TICK / spacing) * spacing;
            if (upper > TickMath.MAX_TICK) upper = (TickMath.MAX_TICK / spacing) * spacing;
            uint256 a0 = (amt0 * WEIGHTS[i]) / BPS;
            uint256 a1 = (amt1 * WEIGHTS[i]) / BPS;
            uint128 liq = LiquidityAmounts.getLiquidityForAmounts(
                sqrtPriceX96, TickMath.getSqrtPriceAtTick(lower), TickMath.getSqrtPriceAtTick(upper), a0, a1
            );
            if (liq == 0) continue;
            bytes32 salt = bytes32(i);
            (BalanceDelta delta,) = POOL_MANAGER.modifyLiquidity(
                _poolKey,
                ModifyLiquidityParams({tickLower: lower, tickUpper: upper, liquidityDelta: int256(uint256(liq)), salt: salt}),
                ''
            );
            owed0 += int256(delta.amount0());
            owed1 += int256(delta.amount1());
            _positions.push(Pos({tickLower: lower, tickUpper: upper, salt: salt}));
        }
        if (owed0 < 0) _settle(_poolKey.currency0, uint256(-owed0));
        if (owed1 < 0) _settle(_poolKey.currency1, uint256(-owed1));
    }

    function _withdraw() internal {
        PoolId poolId = _poolKey.toId();
        int256 owed0;
        int256 owed1;
        for (uint256 i; i < _positions.length; ++i) {
            Pos memory p = _positions[i];
            uint128 liq = POOL_MANAGER.getPositionLiquidity(
                poolId, keccak256(abi.encodePacked(address(this), p.tickLower, p.tickUpper, p.salt))
            );
            if (liq == 0) continue;
            (BalanceDelta delta,) = POOL_MANAGER.modifyLiquidity(
                _poolKey,
                ModifyLiquidityParams({tickLower: p.tickLower, tickUpper: p.tickUpper, liquidityDelta: -int256(uint256(liq)), salt: p.salt}),
                ''
            );
            owed0 += int256(delta.amount0());
            owed1 += int256(delta.amount1());
        }
        if (owed0 > 0) POOL_MANAGER.take(_poolKey.currency0, address(this), uint256(owed0));
        if (owed1 > 0) POOL_MANAGER.take(_poolKey.currency1, address(this), uint256(owed1));
    }

    function _mintSide(address minter, uint256 budget) internal returns (uint256) {
        if (minter == address(0)) return budget;
        Currency.unwrap(CURRENCY).safeApproveWithRetry(minter, budget);
        return ITokenMinter(minter).mint(budget);
    }

    function _settle(Currency currency, uint256 amount) internal {
        POOL_MANAGER.sync(currency);
        currency.transfer(address(POOL_MANAGER), amount);
        POOL_MANAGER.settle();
    }
}
