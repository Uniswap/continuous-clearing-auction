# RWA Launcher — Specification

> Status: **Draft / design**. This document specifies a new auction product, the **RWA Launcher**, that reuses the [Continuous Clearing Auction (CCA)](../README.md) uniform-clearing engine and the [Uniswap Liquidity Launcher](https://github.com/Uniswap/liquidity-launcher) for pool initialization.

## 1. Summary

An RWA (Real World Asset) issuer wants to bootstrap a community of LPs to market-make their token (e.g. `OIL`) for a fixed period. Instead of selling the token itself (as a CCA does), the RWA Launcher lets the issuer **pre-build a two-sided concentrated liquidity position and sell fractional shares of it** to the community via a **uniform-price reverse auction on a discount**.

The mechanism in one paragraph:

> The issuer deposits a notional `D` of USDC (e.g. `$2M`) and grants the contract mint/redeem authority over the RWA token. Bidders bid, over time, a **discount** (in bps) off the position's assumed end value — which is taken to be `D` — that they require in order to participate. At the end of the auction the bids are walked best→worst (lowest discount first) until `D` of shares are sold; everyone clears at the single marginal **clearing discount** `d*`. Proceeds (`≈ D · (1 − d*)`) go to the **issuer**. The contract then converts half of `D` into the RWA token via the mint contract and deposits `D/2` USDC + `D/2` RWA into a Uniswap v4 pool as one or more concentrated positions. Winning bidders hold shares of that position, market-make for the LP duration (e.g. 1 week), and afterwards redeem their shares for the pro-rata underlying plus accrued fees.

The issuer's net cost is the discount `d* · D` — the incentive paid to the community for taking a fixed period of inventory/IL risk while seeding deep liquidity.

## 2. Relationship to the CCA

The RWA Launcher is **structurally the CCA, mirrored onto a discount axis.** A bidder demanding discount `d` (bps) is exactly equivalent to a CCA bidder willing to pay a fractional-NAV price `p = 1 − d/10000`:

| Bidder intent | Discount form | CCA price form |
| --- | --- | --- |
| Wants no discount (most generous) | `d = 0` | `p = 1.0` (pay full NAV) |
| Wants 10 bps off | `d = 10` | `p = 0.9990` |
| Will only participate at ≥ 100 bps off | `d = 100` | `p = 0.9900` (= floor) |

Because **lower discount = higher fractional price = better for the issuer**, the CCA's "higher price wins, clear at the lowest accepted price" logic applies *verbatim* once bids are expressed as `p`. No comparator needs to be rewritten — only the parameterization and the post-auction settlement change.

### Concept mapping

| CCA concept | RWA Launcher analog |
| --- | --- |
| `TOKEN` being sold | **Position-share token** — fungible claim on the built LP position (v1) |
| `TOTAL_SUPPLY` | Total shares = `D` notional units (e.g. 1 share = `$1`) |
| `currency` (raised) | USDC paid by bidders → routed to issuer |
| Tick = Q96 price level | Tick = Q96 **price per share in USDC** over `[floor, ONE_Q96]`, where `ONE_Q96 = 2^96` is the full-NAV (zero-discount) price of a `$1` share |
| `MAX_BID_PRICE` (`= MaxBidPriceLib.maxBidPrice(TOTAL_SUPPLY)`) | **Unchanged** — still the supply-derived overflow/sanity ceiling from `MaxBidPriceLib`. It is *not* the economic cap. The economic "zero discount" cap is `ONE_Q96` (full NAV); the constructor requires `MAX_BID_PRICE ≥ ONE_Q96` (and `floor + tickSpacing ≤ MAX_BID_PRICE`, see `ContinuousClearingAuction.sol:86-91`) so that a `$1` share can be bid at full NAV. |
| `floorPrice` | `ONE_Q96 · (1 − maxDiscount/10000)` (the worst discount the issuer will accept) |
| `clearingPrice` `p*` | `ONE_Q96 · (1 − d*/10000)` (uniform clearing price per share) |
| Bid `maxPriceQ96`, `amount` | Bid `maxPriceQ96 = ONE_Q96 · (1 − d/10000)`, `amount = shares` |
| `requiredCurrencyRaised` / graduation | Threshold shares sold for the position to be built |
| `tokensRecipient` (unsold) | Issuer retains unsold shares (becomes co-LP) |
| `fundsRecipient` | Issuer (receives auction proceeds) |
| `onTokensReceived()` | Issuer deposits `D` USDC + pre-minted share supply |
| `lbpInitializationParams()` handoff | **Extended**: build multi-range v4 position via mint + LBP |
| `IValidationHook` (ERC1155 gating) | Reusable as-is for gated RWA participation |
| Continuous/time-weighted clearing over steps | Reused for over-time, timing-game-resistant bidding |

### What is genuinely new (beyond CCA)

1. **Mint integration** — convert `D/2` USDC → RWA token at build time (the only oracle the system needs).
2. **Multi-tranche concentrated position builder** — seed v4 positions at several range widths (`5 / 10 / 50 / 100 bp`).
3. **Position-share token + redemption** — what winners claim is a redeemable share, not the project token.
4. **LP-duration lifecycle** — an active market-making window followed by a keeper-triggered unwind and pull-based redemption.

## 3. Goals & non-goals

**Goals**
- Bootstrap a community-owned, deep, concentrated MM position for an RWA token with one transaction-ish flow for the issuer.
- Fair, timing-game-resistant price (discount) discovery via the CCA's continuous uniform clearing.
- Oracle-free auction: the discount references the issuer's own deposited notional, not an external NAV feed.
- Maximize reuse of audited CCA and Liquidity Launcher code.

**Non-goals (v1)**
- Per-tranche bidding (v1 sells shares of the *whole* multi-range bundle — see §11).
- Active rebalancing of positions during the LP window.
- Secondary transfer/market for shares before unwind (shares may be transferable, but no protocol-level marketplace).
- Supporting non-pegged / highly volatile RWAs where the "assumed end value = `D`" approximation breaks down.

## 4. Actors

| Actor | Role |
| --- | --- |
| **Issuer** | Deposits `D` USDC, grants mint/redeem authority, receives auction proceeds and any unsold shares. Configures tranches and timing. |
| **Bidder / LP** | Submits `(shares, discount)` bids over the auction window; on win, holds position shares and redeems after the LP window. |
| **Mint contract** | Issuer-controlled contract that converts USDC ↔ RWA token at a known rate. The sole price source. |
| **Keeper** | Permissionless actor that triggers checkpointing, position build, and the post-window unwind. |

## 5. Mechanism

### 5.1 Bidding

Bidders submit, over the auction window, a bid of:
- `shares` — notional size of position they want to own (USDC-denominated, e.g. `$500k`).
- `discount` — bps off NAV they require (`0` = full price, `10` = 10 bps off, capped at `maxDiscount`).

Internally the bid is stored as a CCA bid with `maxPriceQ96 = ONE_Q96 · (1 − discount/10000)` and `amount = shares` (`ONE_Q96 = 2^96` is the full-NAV price of one `$1` share). Bidders escrow up to `shares · ONE_Q96` worth of USDC (i.e. full NAV); the overpay above the clearing price is refunded, exactly as the CCA refunds the difference between `maxPrice` and `clearingPrice`.

### 5.2 Clearing

At finalization the engine walks ticks from the highest price (lowest discount) downward, accumulating `shares` until cumulative reaches `D` (total share supply) or demand is exhausted:
- **Clearing price** `p*` (per share, Q96) = the price at the marginal tick that fills the supply; **clearing discount** `d* = (1 − p*/ONE_Q96) · 10000` bps.
- Every winning bidder pays `p*` per share — i.e. receives the *same* discount `d*`, which is ≥ what they demanded.
- Partial fill at the marginal tick uses the CCA's existing pro-rata logic.
- **Oversubscription** at zero discount → `p*` capped at `ONE_Q96` (`d* = 0`); excess demand pro-rata'd at the top tick.
- **Undersubscription** (demand at `maxDiscount` < `D`) → see graduation (§6.3).

### 5.3 Settlement (position build)

Once finalized and graduated, the contract builds the position from the issuer's deposited `D`:
1. Split `D` into `D/2` USDC + `D/2` to be converted.
2. Call `mint(D/2)` on the mint contract → receive RWA tokens; the mint rate (`navQ96`, oriented as the pool's `token1/token0` — see §7.2) sets the **pool init price**.
3. Initialize / add liquidity to the v4 pool: deposit USDC + RWA across the configured tranches at ranges centered on the init price (§7.3).
4. Route auction **proceeds** (`Σ winning shares · p* / ONE_Q96` USDC) to the issuer (`fundsRecipient`).
5. Mint/assign position shares to winners (claimable after `claimBlock`); assign any unsold shares to the issuer.

The exact `D/2`-per-side split is the *budget*, not the amount consumed: concentrated liquidity at a finite range absorbs the two assets in a ratio that is only ≈50/50 by value near the init price, so one side is left with residual dust. The build sizes the position to the binding side and returns the dust to the issuer (it is not part of the position shares). See §7.3 and the residual note in §8.

Note the two distinct USDC flows: the issuer's `D` deposit *funds the position*; the bidders' proceeds *reimburse the issuer*. Net issuer cost = the discount (§8).

### 5.4 Market-making window & unwind

- Shares represent a pro-rata claim on the live position(s). Trading fees accrue to the position and therefore to shareholders.
- After `endBlock + lpDuration` (the **unwind block**), a keeper withdraws all liquidity from the pool into the contract (USDC + RWA + accrued fees).
- Shareholders **redeem** (burn shares) for their pro-rata USDC + RWA. RWA can optionally be auto-redeemed to USDC via the mint contract's `redeem` so holders receive a single asset.

## 6. Lifecycle / state machine

```
        deposit D + share supply               auction window                 finalize          build           lpDuration            unwind        pull
Issuer ───────────────────────────▶ [SETUP] ──────────────────▶ [BIDDING] ──────────▶ [CLEARED] ──────▶ [ACTIVE] ───────────────▶ [UNWOUND] ──────▶ redeem
                                        │                            │                     │                │                          │
                                   onTokensReceived           submitBid (over time)   checkpoint()      mint + seed v4           withdraw liquidity
                                                                                       at endBlock       proceeds → issuer
```

### 6.1 SETUP
Issuer deploys via factory with `RWALauncherParameters` (§7.1), deposits `D` USDC, and the contract pre-mints the share supply to itself. `onTokensReceived()` validates both the USDC notional and the share supply are present before bidding can start.

### 6.2 BIDDING
Identical to CCA: `submitBid`, `checkpoint`, time-weighted continuous clearing. Optional `IValidationHook` gates participation.

### 6.3 Graduation
- **Graduated** if shares sold ≥ `requiredSharesSold` (analog of `requiredCurrencyRaised`).
- **Undersubscribed but graduated**: issuer keeps unsold shares and co-LPs the remainder; the full `D` position is still built. *(Default.)*
- **Failed** (below threshold): no position is built; bidders are fully refunded; issuer withdraws `D`. *(Mirror of a non-graduated CCA.)*

### 6.4 ACTIVE → UNWOUND
Keeper-triggered. Liquidity withdrawn into a redemption pot; `redeem(shares)` becomes available.

## 7. Detailed design

### 7.1 Parameters

```solidity
struct RWALauncherParameters {
    address currency;             // USDC (funds raised + position base). address(0) = ETH unsupported for RWA
    address mintContract;         // IRWAMint — converts currency <-> RWA token (the only oracle)
    address fundsRecipient;       // issuer; receives auction proceeds
    address sharesRecipient;      // issuer; receives unsold shares (co-LP)
    uint64  startBlock;           // bidding starts
    uint64  endBlock;             // bidding ends (auction finalize)
    uint64  claimBlock;           // winners can claim shares
    uint64  lpDuration;           // blocks the position stays live after endBlock
    uint256 tickSpacing;          // Q96 granularity of the price-per-share / discount axis
    uint256 maxDiscountBps;       // worst discount issuer will accept -> floorPrice = ONE_Q96 * (1 - maxDiscountBps/1e4)
    uint128 requiredSharesSold;   // graduation threshold (notional)
    TrancheConfig[] tranches;     // v4 range widths + capital weights (e.g. 5/10/50/100 bp)
    address validationHook;       // optional gating (reuses IValidationHook)
    bytes   auctionStepsData;     // reused CCA issuance schedule for share release over time
}

struct TrancheConfig {
    uint24  rangeWidthBps;        // half-width of the concentrated range around the init price (e.g. 5, 10, 50, 100)
    uint16  weightBps;            // share of D/2-per-side allocated to this tranche (sum = 10_000)
    int24   tickSpacing;          // v4 pool tick spacing for this position
}
```

`D` (total notional) and the pre-minted share supply are passed to the constructor like the CCA's `_token` / `_totalSupply`.

### 7.2 Mint contract interface

The only external price dependency. Assumed to convert at a known rate (NAV) controlled by the issuer.

```solidity
interface IRWAMint {
    /// @notice Convert `currencyAmount` of USDC into the RWA token at current NAV
    /// @return rwaAmount tokens minted to msg.sender
    function mint(uint256 currencyAmount) external returns (uint256 rwaAmount);

    /// @notice Convert `rwaAmount` of RWA token back into USDC at current NAV
    /// @return currencyAmount returned to msg.sender
    function redeem(uint256 rwaAmount) external returns (uint256 currencyAmount);

    /// @notice Current NAV, Q96, expressed as the v4 pool's price of token0 in units of token1
    ///         (i.e. token1/token0). The launcher orders the pool currencies and inverts this
    ///         value if needed so it matches `sqrtPriceX96` orientation before initializing.
    function navQ96() external view returns (uint256);
}
```

> **Orientation.** A v4 pool price is `token1/token0`, fixed by the sorted currency order. `navQ96` MUST be interpreted against that ordering: the launcher determines whether USDC or RWA is `token0` and inverts `navQ96` accordingly before deriving `sqrtPriceX96`. Getting this backwards seeds the pool at the inverse price, so the build asserts the resulting price is within a sanity band of `navQ96` (see §10).

### 7.3 Position build

At settlement, with the init price derived from `navQ96()` (oriented per §7.2):
- For each `TrancheConfig`, compute the range `[mid · (1 − w), mid · (1 + w)]` (`w = rangeWidthBps/1e4`) and the per-tranche capital budget `D/2 · weightBps/1e4` per side.
- Add liquidity to the v4 pool for each range. Position NFTs / liquidity are held by the launcher contract; shares are the claim on the aggregate.
- **Residual handling.** Because each range absorbs the two assets in a ratio set by the v4 liquidity math (only ≈50/50 by value at the init price, and not exactly so for an arithmetically-symmetric range), the `D/2`-per-side figures are budgets, not exact deposits. Per tranche, the launcher computes the liquidity bounded by the scarcer side and deposits the matching amount of the other; leftover dust on the abundant side is summed across tranches and returned to the issuer. The position shares represent only what was actually deposited.
- **Pool creation.** The launcher itself initializes (or reuses) the v4 pool and adds the multi-range liquidity directly — it does *not* hand off to an external creator. It still *implements* `ILBPInitializer` (§9) so downstream tooling can read the resulting `{initialPriceX96, tokensSold, currencyRaised}`; that interface is a read surface, not the thing that creates the pool.

### 7.4 Position shares & redemption

- v1: a **single fungible share token** (e.g. ERC20 or ERC6909 id) representing a pro-rata claim on the whole multi-range bundle. (ERC6909/ERC1155 chosen if/when per-tranche shares land — see §11.)
- Claiming: reuse CCA `claimTokens` / `claimTokensBatch`; the claimed asset is the share token.
- Redemption (post-unwind): `redeem(shareAmount)` burns shares and transfers pro-rata `USDC + RWA` from the redemption pot. Optional flag to auto-`redeem` RWA→USDC so the holder receives only USDC.

## 8. Economic accounting — worked `$2M` example

Issuer deposits `D = $2,000,000`. Total shares = `2,000,000` (1 share = `$1`). `maxDiscountBps = 100` → floor price `0.9900` (i.e. `0.9900 · ONE_Q96`).

| Bid | Shares | Discount (bps) | Price `p` per share |
| --- | --- | --- | --- |
| A | 800,000 | 0 | 1.0000 |
| B | 600,000 | 5 | 0.9995 |
| C | 700,000 | 10 | 0.9990 |
| D | 500,000 | 20 | 0.9980 |

Walk best→worst, accumulating shares to the `D = 2.0M`-share target: A (cum. 800k) → B (cum. 1.4M) → C crosses 2.0M, so C fills `2.0M − 1.4M = 600k` of its 700k (100k of C left unfilled). **D loses entirely.**

- **Clearing discount `d* = 10 bps`** (`p* = 0.9990`, C is the marginal tick).
- Winners A (800k), B (600k) and C (600k) — `2.0M` shares total — all pay `0.9990`/share.
- **Proceeds to issuer** = `2,000,000 · 0.9990 = $1,998,000`.
- **Issuer discount cost** = `$2,000` (`= d* · D`).

Build: `$1,000,000` USDC → `mint` → RWA; deposit `$1M USDC + $1M RWA` (less residual dust returned to the issuer — see §7.3) across tranches.

Issuer cash flow: `−$2,000,000` (deposit) `+ $1,000,000` (mint backing held in reserve against the RWA liability) `+ $1,998,000` (proceeds) `= +$998,000` cash, against `$1,000,000` of RWA liability now circulating → **net `−$2,000` = the discount.** The community owns a `$2M` position they paid `$1.998M` for.

## 9. Liquidity Launcher reuse

Reuse as much of the audited stack as possible while keeping the new surface clean:

- **`IDistributorFactory` / `IDistributor`** — deploy the `RWALauncher` the same way the CCA factory deploys auctions (`create(token, amount, configData, salt)`), so it slots into the existing distribution tooling. See [`ContinuousClearingAuctionFactory.sol`](../src/ContinuousClearingAuctionFactory.sol).
- **`ILBPInitializer` (read surface, not a creator)** — the auction *implements* `lbpInitializationParams()` ([`ContinuousClearingAuction.sol:134`](../src/ContinuousClearingAuction.sol)), a `view` that returns `{ initialPriceX96, tokensSold, currencyRaised }` for downstream tooling to read; the Liquidity Launcher (the *consumer*) is what reads it. In the RWA Launcher the contract creates and seeds the multi-range pool itself (§7.3) and continues to implement `ILBPInitializer` so the same downstream tooling can read its post-build state (with `initialPriceX96` = the oriented `navQ96` init price).
- **`IProtocolFeeController` / `ProtocolFeeLib`** — reuse for protocol fees on proceeds, identical to the CCA.
- **Clearing engine** — reuse `BidStorage`, `TickStorage`, `CheckpointStorage`, `StepStorage`, `DemandLib`, `PriceLib`, `MaxBidPriceLib`, the checkpoint/exit/claim flow, and `IValidationHook`. Only the parameterization (`floor = ONE_Q96 · (1 − maxDiscount)`, with `MAX_BID_PRICE` left as the supply-derived `MaxBidPriceLib` ceiling — see §2) and post-auction settlement differ.

**New contracts**
- `RWALauncher.sol` — extends the CCA storage/clearing mixins; adds settlement (mint + multi-range seed), share token, redemption, unwind.
- `RWALauncherFactory.sol` — analog of `ContinuousClearingAuctionFactory`.
- `interfaces/IRWALauncher.sol`, `interfaces/IRWAMint.sol`.
- Optional `RWALauncherLens.sol` — analog of `CCALens` for offchain reads.

## 10. Security & correctness considerations

- **Mint-rate manipulation**: the pool mid comes entirely from `navQ96()` at build time. A compromised/mispriced mint contract mis-seeds the pool. Mitigations: sanity bounds on `navQ96` vs. expected, issuer-trust assumption documented, optional two-sided deposit checks.
- **Build atomicity**: mint + multi-range seed + proceeds routing should be a single settled transition; partial failure must not strand `D`. Consider a `finalize → build` split with a failure path that returns `D` to the issuer and refunds bidders.
- **"Assumed end value = `D`" approximation**: only sound when the RWA is pegged-ish and the build happens promptly at end. Volatile assets break the discount semantics (documented non-goal).
- **Undersubscription / graduation**: must mirror the CCA's well-audited non-graduation refund path; no position is built on failure.
- **Unwind liveness**: redemption must not depend on a single keeper. `redeem` should be callable by anyone post-unwind-block; unwind itself should be permissionless after the window.
- **IL / inventory at redemption**: shareholders bear IL; redemption returns whatever the position is actually worth at unwind (USDC + RWA + fees), which may differ from `D`. The discount is the only guaranteed edge, not principal protection.
- **Reentrancy**: reuse CCA's `ReentrancyGuardTransient`; the mint contract and v4 callbacks are new external-call surfaces to guard.
- **Rounding**: fraction/discount Q96 math reuses CCA's tick/price libs; verify the `p = 1 − d/1e4` transform composes with existing `MaxBidPriceLib` bounds.

## 11. v1 scope vs. future

| Capability | v1 | Future |
| --- | --- | --- |
| Bid on whole multi-range bundle | ✅ | |
| **Per-tranche bidding** (separate clearing per range width) | ❌ | ✅ — bid struct gains a tranche id; one clearing pass per tranche, or a coupled clearing across tranches; shares become ERC6909/ERC1155 per tranche |
| Single fungible share | ✅ | per-tranche shares |
| Auto-redeem RWA→USDC on redemption | optional flag | |
| Active rebalancing during window | ❌ | possible keeper strategy |
| Multiple RWA tokens / multi-asset | ❌ | |

Per-tranche bidding is the main intended evolution: tighter ranges (e.g. ±5 bps) carry more inventory risk and should clear at a higher discount than wide ranges (±100 bps), so independent per-tranche clearing prices price that risk correctly. v1 deliberately starts with one blended clearing discount over the whole bundle for simplicity.

## 12. Open questions

1. **Build trigger & atomicity** — single `finalize()` that also builds, or separate `finalize()` then permissionless `build()`? Failure semantics if `mint`/seed reverts.
2. **Share representation** — ERC20 vs ERC6909 for v1 (affects future per-tranche path).
3. **Fee accrual** — collect v4 fees continuously into the position (auto-compounded) or only at unwind?
4. **Redemption asset** — always return USDC+RWA, always auto-redeem to USDC, or holder's choice?
5. **Undersubscription default** — issuer co-LPs the remainder (current default) vs. scale the position down to shares actually sold.
6. **maxDiscount as floor** — is a hard floor the right cap, or should the auction always build at whatever discount clears (no floor)?

## Glossary

- **`D`** — issuer's deposited notional (the assumed end value of the position).
- **Discount `d` / `d*`** — bps off NAV a bidder requires / the uniform clearing discount.
- **Fraction `p`** — `1 − d/10000`, the share of NAV a bidder pays; the CCA "price" axis.
- **Tranche** — a concentrated v4 position of a given range width (`5 / 10 / 50 / 100 bp`).
- **Share** — fungible claim on the built position; what winners receive and later redeem.
- **Unwind** — post-`lpDuration` withdrawal of liquidity into the redemption pot.
