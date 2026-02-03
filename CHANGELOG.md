# Changelog

## v1.1.0 (latest)

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
