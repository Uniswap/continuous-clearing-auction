# Changelog

## v1.1.0 (latest)

Fully backwards compatible with Liquidity Launcher v1.0.0 deployments. Contains bug fixes, periphery contracts, and implements the new ILBPInitializer interface introduced in Liquidity Launcher v1.1.0.

### Added

- New function `forceIterateOverTicks` to manually iterate over ticks and update the clearing price
- New state variable `$clearingPrice` to store the current clearing price
- New package `blocknumberish` to handle block number retrieval on different chains (to support Arbitrum)
- `IContinuousClearingAuction.lbpInitializationParams` to return the initialization parameters for the LBP initializer
- `IContinuousClearingAuction.supportsInterface` to check if the contract supports the LBP initializer interface

### Changed

- Some minor code quality changes
- Fixed an issue in error parameter order

### Audits

### Deployment addresses

**ContinuousClearingAuctionFactory**
| Network | Address | Commit Hash | Version |
| -------- | ------------------------------------------ | ---------------------------------------- | ---------------- |
| Mainnet | 0xcca1101C61cF5cb44C968947985300DF945C3565 | 95d7da7a2d25cf60f14eaccd6ab5fb24d393a452 | v1.1.0 |
| Unichain | 0xcca1101C61cF5cb44C968947985300DF945C3565 | 95d7da7a2d25cf60f14eaccd6ab5fb24d393a452 | v1.1.0 |
| Base | 0xcca1101C61cF5cb44C968947985300DF945C3565 | 95d7da7a2d25cf60f14eaccd6ab5fb24d393a452 | v1.1.0 |
| Sepolia | 0xcca1101C61cF5cb44C968947985300DF945C3565 | 95d7da7a2d25cf60f14eaccd6ab5fb24d393a452 | v1.1.0 |

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
