# Changelog

## v2.0.0 (latest)

Major release with breaking changes to the auction constructor, factory constructor, sweep authorization, and a number of interface renames. Adds supply rollover settlement math, a protocol fee controller, and new lens contracts for offchain reads. Integrators must redeploy and update integrations.

### Changed

- **Breaking:** Moved `ClaimBlockIsBeforeEndBlock`, `NotClaimable`, and `AuctionIsNotOver` errors out of `IContinuousClearingAuction` and into `IStepStorage`. Integrators importing these from the auction interface must update imports. ([#321](https://github.com/Uniswap/continuous-clearing-auction/pull/321))
- Added `CCALens` and `TickDataLens` periphery contracts for offchain reads of auction state and initialized tick data. Non-breaking addition. ([#325](https://github.com/Uniswap/continuous-clearing-auction/pull/325))
- **Breaking:** `sweepCurrency()` is now restricted to `FUNDS_RECIPIENT` and `sweepUnsoldTokens()` is now restricted to `TOKENS_RECIPIENT`. Adds new `NotAuthorized(address authorized, address caller)` error. Callers other than the configured recipients will revert. ([#329](https://github.com/Uniswap/continuous-clearing-auction/pull/329))
- **Breaking:** Reworked auction settlement to support supply rollover so that demand above the clearing price carries forward over the remaining schedule. Adds new getters `remainingSupplyQ96X7`, `remainingSupply`, `requiredDemandQ96`, and `requiredDemandQ96AtNextActiveTick`. Final clearing prices, per-block fills, and bid economics may differ from v1.x for the same inputs. ([#327](https://github.com/Uniswap/continuous-clearing-auction/pull/327))
- **Breaking:** Added optional custody tokens to `AuctionParameters` and changed `TokensReceived` event signature. ([#330](https://github.com/Uniswap/continuous-clearing-auction/pull/330))
- Removed obsolete DoS test. Non-breaking. ([#333](https://github.com/Uniswap/continuous-clearing-auction/pull/333))
- **Breaking:** Renamed `ITokenCurrencyStorage` to `IAuctionStorage` and moved `currencyRaised`, `currencyRaisedQ96X7`, `sumCurrencyDemandAboveClearingQ96`, `totalCleared`, `totalClearedQ96X7`, `remainingSupply`, and `remainingSupplyQ96X7` into that interface. Renamed `currencyRaisedQ96_X7` → `currencyRaisedQ96X7` and `totalClearedQ96_X7` → `totalClearedQ96X7`. ([#332](https://github.com/Uniswap/continuous-clearing-auction/pull/332))
- Fixed an edge case where the clearing price could be incorrectly advanced when rounding caused `remainingSupply` to reach zero before the schedule completed. New bids submitted with zero remaining supply now revert. ([#331](https://github.com/Uniswap/continuous-clearing-auction/pull/331))
- **Breaking:** Reverted the custody tokens feature from [#330](https://github.com/Uniswap/continuous-clearing-auction/pull/330). `AuctionParameters.custodyTokens` and the `custodyTokens()` getter are removed; `TokensReceived` event reverts to `(uint256 totalSupply)`. ([#335](https://github.com/Uniswap/continuous-clearing-auction/pull/335))
- **Breaking:** Tightened `MIN_FLOOR_PRICE` from `2^32` to `2^32 + 1` so that its Q96 reciprocal fits in a `uint160` for downstream LBP / v4 initialization math. Auctions configured with floor price exactly `2^32` are no longer accepted. ([#336](https://github.com/Uniswap/continuous-clearing-auction/pull/336))
- Internal refactor to call `CheckpointAccountingLib` helpers directly from `ContinuousClearingAuction`, removing thin wrappers from `CheckpointStorage`. Non-breaking. ([#338](https://github.com/Uniswap/continuous-clearing-auction/pull/338))
- **Breaking:** Added an owner-controlled `IProtocolFeeController` and threaded it through the factory and auction. `ContinuousClearingAuctionFactory` constructor now takes `address _protocolFeeController` and exposes a `protocolFeeController()` getter; `ContinuousClearingAuction` constructor takes an additional `address _protocolFeeController` argument. `sweepCurrency()` now transfers the protocol fee to the controller and sweeps `currencyRaised − protocolFee` to the funds recipient. `currencyRaised()` no longer subtracts protocol fees, and `lbpInitializationParams()` returns the post-fee `currencyRaised`. `ILBPInitializer` is now imported from the `liquidity-launcher` submodule rather than `src/interfaces/external`. ([#340](https://github.com/Uniswap/continuous-clearing-auction/pull/340))
- Updated `TickDataLens` to use the rollover-aware `requiredDemandQ96` helper so tick data reflects the remaining supply over the remaining issuance schedule. ([#334](https://github.com/Uniswap/continuous-clearing-auction/pull/334))
- **Breaking:** `lbpInitializationParams()` now reverts with `NotGraduated` if the auction did not graduate. Previously it returned stale values for unsuccessful auctions. ([#342](https://github.com/Uniswap/continuous-clearing-auction/pull/342))
- Expanded stateful invariant test coverage. Test-only, non-breaking. ([#337](https://github.com/Uniswap/continuous-clearing-auction/pull/337))

### Audits

### Deployment addresses

**ContinuousClearingAuctionFactory**
| Network | Address | Commit Hash | Version |
| -------- | ------------------------------------------ | ---------------------------------------- | ---------------- |
| Mainnet | | | v2.0.0 |
| Unichain | | | v2.0.0 |
| Base | | | v2.0.0 |
| Sepolia | | | v2.0.0 |
| Unichain Sepolia | | | v2.0.0 |

## v1.1.0

Fully backwards compatible with Liquidity Launcher v1.0.0 deployments. Contains bug fixes, periphery contracts, and implements the new ILBPInitializer interface introduced in Liquidity Launcher v1.1.0.

### Added

- New function `forceIterateOverTicks` to manually iterate over ticks and update the clearing price
- New state variable `$clearingPrice` to store the current clearing price
- New package `blocknumberish` to handle block number retrieval on different chains (to support Arbitrum)
- `IContinuousClearingAuction.lbpInitializationParams` to return the initialization parameters for the LBP initializer
- `IContinuousClearingAuction.supportsInterface` to check if the contract supports the LBP initializer interface
- Added `ValidationHookIntrospection` to existing ValidationHook contracts to support introspection via ERC165

### Changed

- Fixed a bug in certain rare edge cases which would cause bids to be permanently locked in the contract
- Fixed an issue in error parameter order
- Some minor code quality changes

### Audits

### Deployment addresses

**ContinuousClearingAuctionFactory**
| Network | Address | Commit Hash | Version |
| -------- | ------------------------------------------ | ---------------------------------------- | ---------------- |
| Mainnet | 0xCCccCcCAE7503Cac057829BF2811De42E16e0bD5 | 8508f332c3daf330b189290b335fd9da4e95f3f0 | v1.1.0 |
| Unichain | 0xCCccCcCAE7503Cac057829BF2811De42E16e0bD5 | 8508f332c3daf330b189290b335fd9da4e95f3f0 | v1.1.0 |
| Base | 0xCCccCcCAE7503Cac057829BF2811De42E16e0bD5 | 8508f332c3daf330b189290b335fd9da4e95f3f0 | v1.1.0 |
| Sepolia | 0xCCccCcCAE7503Cac057829BF2811De42E16e0bD5 | 8508f332c3daf330b189290b335fd9da4e95f3f0 | v1.1.0 |
| Unichain Sepolia | 0xCCccCcCAE7503Cac057829BF2811De42E16e0bD5 | 8508f332c3daf330b189290b335fd9da4e95f3f0 | v1.1.0 |

## v1.0.0

Initial deployment of CCA.

### Deployment addresses

**ContinuousClearingAuctionFactory**
| Network | Address | Commit Hash | Version |
| -------- | ------------------------------------------ | ---------------------------------------- | ---------------- |
| Mainnet | 0x0000ccaDF55C911a2FbC0BB9d2942Aa77c6FAa1D | 154fd189022858707837112943c09346869c964f | v1.0.0-candidate |
| Unichain | 0x0000ccaDF55C911a2FbC0BB9d2942Aa77c6FAa1D | 154fd189022858707837112943c09346869c964f | v1.0.0-candidate |
| Base | 0x0000ccaDF55C911a2FbC0BB9d2942Aa77c6FAa1D | 154fd189022858707837112943c09346869c964f | v1.0.0-candidate |
| Sepolia | 0x0000ccaDF55C911a2FbC0BB9d2942Aa77c6FAa1D | 154fd189022858707837112943c09346869c964f | v1.0.0-candidate |
