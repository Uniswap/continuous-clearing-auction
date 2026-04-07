# Plan: `remainingSupplyQ96X7` guard in `_checkpointAtBlock`

## Context

A new inner guard was added in `_checkpointAtBlock` (line 287) to skip the sell/accounting logic when `remainingSupplyQ96X7() == 0`, even if `deltaMps > 0`:

```solidity
if (deltaMps > 0) {
    ValueX7 remainingSupplyQ96X7_ = remainingSupplyQ96X7();
    if (ValueX7.unwrap(remainingSupplyQ96X7_) > 0) {
        // ... token/currency accounting + cumulativeMps advancement ...
    }
}
```

This prevents selling phantom tokens if rounding ever pushes `$totalClearedQ96_X7 >= TOTAL_SUPPLY_Q96_X7` before `cumulativeMps` reaches `MPS`.

## How `remainingSupplyQ96X7` trends toward zero

`remainingSupplyQ96X7 = TOTAL_SUPPLY_Q96_X7 - $totalClearedQ96_X7` (clamped via `saturatingSub`).

`$totalClearedQ96_X7` grows each checkpoint via:

```solidity
tokensClearedQ96X7 = currencyRaisedDeltaQ96X7.toTokensRoundingUp(clearingPriceQ96);
$totalClearedQ96_X7 += tokensClearedQ96X7;
```

The `toTokensRoundingUp` call uses `fullMulDivUp(currency, Q96, price)`, which rounds **up** by design. This means `$totalClearedQ96_X7` accumulates +1 unit of dust per checkpoint in the worst case. Over N checkpoints, the cumulative overcount is O(N).

Meanwhile, `TOTAL_SUPPLY_Q96_X7 = totalSupply * Q96 * MPS`, which is an enormous number for any realistic auction. The gap between `$totalClearedQ96_X7` and `TOTAL_SUPPLY_Q96_X7` at the final checkpoint is driven by the actual remaining supply, minus the cumulative dust. For the gap to close prematurely (supply hits zero before schedule ends), the cumulative dust would need to equal the remaining supply — practically unreachable.

**Nevertheless, the guard is correct to have.** The cost is a warm SLOAD and it eliminates an entire class of edge-case accounting errors.

## The open question: should `cumulativeMps` advance when supply is zero?

Currently both `cumulativeMps` and `cumulativeMpsPerPrice` are inside the inner `if`, so they freeze when `remainingSupplyQ96X7 == 0`. There are two options:

### Option A: Freeze the schedule (current implementation)

`cumulativeMps` does not advance. The checkpoint is inserted with stale `cumulativeMps`.

**Pros:**
- `cumulativeMpsPerPrice` stays consistent — it's a weighted inverse-price sum that must track actual token sales. Adding `deltaMps / price` without selling tokens would distort the `calculateFill` math used in bid exits.
- Simple: no special-casing needed.

**Cons / second-order effects:**
- `remainingMpsInAuction()` never reaches 0, so `AuctionSoldOut` never triggers in `_submitBid`. Bids can still be submitted even though no more tokens will be sold. Those bids would be fully refunded at exit, but this is a UX footgun.
- `_iterateOverTicksAndFindClearingPrice` is called on every subsequent checkpoint (because `remainingMpsInAuction > 0` at line 256), though it returns immediately at line 201. Minor gas waste.
- At `END_BLOCK`, `_getFinalCheckpoint` creates a checkpoint via `_checkpointAtBlock(END_BLOCK)`. `deltaMps` for this call would be `MPS - cumulativeMps` (the full remainder). But supply is zero, so the inner guard skips everything. The final checkpoint has `cumulativeMps < MPS`.
- `calculateFill` (used in `exitBid` / `claimTokens`) computes `currencySpentQ96 = bid.amountQ96 * cumulativeMpsDelta / mpsRemainingAfterSubmission`. If the final `cumulativeMps` is less than `MPS`, the `cumulativeMpsDelta` for the last period is smaller than expected, meaning bids submitted early compute a smaller `currencySpent` and get a larger refund. Conversely, `tokensFilled` uses `cumulativeMpsPerPriceDelta` which is also smaller, so fewer tokens are allocated. This could leave tokens stranded in the contract (already cleared but never claimed).
- `sweepUnsoldTokens` uses `remainingSupplyQ96X7()` which is zero (via `saturatingSub`), so it sweeps 0. But `totalCleared > totalSupply` (from the rounding overshoot), so the actual token balance might not fully reconcile.

### Option B: Advance schedule, skip accounting

Move `cumulativeMps += deltaMps` outside the inner guard (but keep `cumulativeMpsPerPrice` inside):

```solidity
if (deltaMps > 0) {
    ValueX7 remainingSupplyQ96X7_ = remainingSupplyQ96X7();
    if (ValueX7.unwrap(remainingSupplyQ96X7_) > 0) {
        // ... full sell logic including cumulativeMpsPerPrice ...
    }
    // Always advance the schedule
    _checkpoint.cumulativeMps += deltaMps;
}
```

**Pros:**
- `cumulativeMps` reaches `MPS` at `END_BLOCK` as expected.
- `AuctionSoldOut` triggers correctly, preventing pointless bid submissions.
- `remainingMpsInAuction()` check at line 256 correctly skips tick iteration once `cumulativeMps == MPS`.

**Cons:**
- `cumulativeMpsPerPrice` must NOT advance (it tracks actual sales). This creates a period where `cumulativeMps` advanced but `cumulativeMpsPerPrice` didn't. For `calculateFill`, this means `cumulativeMpsDelta` includes blocks with no sales, inflating `currencySpent` relative to `tokensFilled`. Bidders in this period would overpay (spend more currency for fewer tokens).
- More precisely: `currencySpent = amount * cumulativeMpsDelta / mpsRemaining` grows, but `tokensFilled = amount * cumulativeMpsPerPriceDelta / (1<<192 * mpsRemaining)` stays flat. The `tokensFilled` would be correct (no tokens were sold), but `currencySpent` would overcharge bidders for a period where nothing happened.
- This can be mitigated if the exit logic accounts for the discrepancy, but it adds complexity.

### Option C: Advance both, using the last known price

Move both outside the inner guard, using the stale clearing price for `cumulativeMpsPerPrice`:

```solidity
if (deltaMps > 0) {
    ValueX7 remainingSupplyQ96X7_ = remainingSupplyQ96X7();
    uint256 clearingPriceQ96 = _checkpoint.clearingPrice;
    if (ValueX7.unwrap(remainingSupplyQ96X7_) > 0) {
        // ... full sell logic ...
    }
    _checkpoint.cumulativeMps += deltaMps;
    _checkpoint.cumulativeMpsPerPrice += (uint256(deltaMps) << 192) / clearingPriceQ96;
}
```

**Pros:**
- Schedule reaches `MPS`. `AuctionSoldOut` works.
- `calculateFill` gets consistent deltas — `cumulativeMpsDelta` and `cumulativeMpsPerPriceDelta` both advance proportionally.
- Bidders above the clearing price get correct `tokensFilled` and `currencySpent` values even in this edge window, because the math assumes tokens were "sold" at the last clearing price (which is the best available approximation).

**Cons:**
- `cumulativeMpsPerPrice` now includes phantom contributions. The accounting "pretends" tokens were sold at the clearing price when they weren't. This is a lie, but a consistent one — the `currencyRaised` and `totalCleared` values don't reflect it, creating a subtle mismatch between what the checkpoint claims happened and what actually happened.
- For partially filled bids at the clearing price tick, `currencyRaisedAtClearingPriceQ96_X7` didn't advance, so their fill calculation is unaffected. But for fully filled bids above clearing, the phantom `cumulativeMpsPerPrice` contribution means they're allocated tokens that were never actually cleared. This could cause insolvency if those bids try to claim.

## Recommendation

Given the scenario is practically unreachable (O(N) dust vs O(totalSupply * Q96 * MPS) gap), **Option A (freeze) is the safest choice**. The second-order effects (stale `cumulativeMps`, bids accepted but refundable) are benign compared to the insolvency risks in Options B and C.

If the UX concern about accepting bids after supply exhaustion matters, a simpler fix would be to add a `remainingSupplyQ96X7() > 0` check in `_submitBid` alongside `remainingMpsInAuction() > 0`.

## Open items

- [ ] Confirm that `calculateFill` with frozen `cumulativeMps` doesn't cause over/under-allocation for bids spanning the freeze boundary
- [ ] Decide if `_submitBid` should also guard on `remainingSupplyQ96X7() > 0`
- [ ] Write test: checkpoint with `remainingSupplyQ96X7 == 0` does not update `$totalClearedQ96_X7`, `$currencyRaisedQ96_X7`, or `cumulativeMps`
