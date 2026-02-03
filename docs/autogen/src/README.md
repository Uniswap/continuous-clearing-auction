# Continuous Clearing Auction

This repository contains the smart contracts for Continuous Clearing Auctions (CCAs). It is intended to be used in combination with the [Uniswap Liquidity Launcher](https://github.com/Uniswap/liquidity-launcher) contracts suite.

## Table of Contents

- [Installation](#installation)
- [Deployments](#deployments)
- [Audits](#audits)
- [Docs](#docs)
- [Repository Structure](#repository-structure)
- [License](#license)

## Overview

CCA is a novel auction mechanism that generalizes the uniform-price auction into continuous time. It provides fair price discovery for bootstrapping initial liquidity while eliminating timing games and encouraging early participation (see [whitepaper](./docs/assets/whitepaper.pdf)).

The contracts can be used as a standalone auction or a part of a larger token distribution system. All contracts are MIT licensed.

## Installation

```bash
forge install
forge build
forge test
```

## Deployments

CCA instances are deployed via the [ContinuousClearingAuctionFactory](./src/ContinuousClearingAuctionFactory.sol).

Addresses are cannonical across select EVM chains. If it is not already deployed, it can be deployed by anyone following the [Deployment Guide](./docs/DeploymentGuide.md).

### ContinuousClearingAuctionFactory

| Network  | Address                                    | Commit Hash                              | Version          |
| -------- | ------------------------------------------ | ---------------------------------------- | ---------------- |
| v1.1.0   | 0xCCccCcCAE7503Cac057829BF2811De42E16e0bD5 | 8508f332c3daf330b189290b335fd9da4e95f3f0 | v1.1.0           |
| v1.0.0\* | 0x0000ccaDF55C911a2FbC0BB9d2942Aa77c6FAa1D | 154fd189022858707837112943c09346869c964f | v1.0.0-candidate |

> \*v1.0.0-candidate is the initial version of CCA and is NOT recommended for production use. For more details, see the [Changelog](./CHANGELOG.md).

## Audits

The code has been audited by Spearbit, OpenZeppelin, and ABDK Consulting. The most recent audits for v1.1.0 are linked below. For a full list of audits, see [Audits](./docs/audits/README.md).

| Version | Date       | Report |
| ------- | ---------- | ------ |
| v1.1.0  | 01/23/2026 | [OpenZeppelin](./docs/audits/OpenZeppelin_v1.1.0.pdf)                |
| v1.1.0  | 01/22/2026 | [Spearbit](./docs/audits/Spearbit_v1.1.0.pdf) and [additional](./docs/audits/Spearbit_v1.1.0_additional.pdf) |

### Bug bounty

The files under `src/` are covered under the Uniswap Labs bug bounty program [here](https://cantina.xyz/code/f9df94db-c7b1-434b-bb06-d1360abdd1be/overview), subject to scope and other limitations.

### Security contact

security@uniswap.org

### Whitepaper

The [whitepaper](./docs/assets/whitepaper.pdf) for the Continuous Clearing Auction.

## Docs

- [Technical documentation](./docs/TechnicalDocumentation.md)
- [Changelog](./CHANGELOG.md)
- [Deployment guide](./docs/DeploymentGuide.md)

## Repository Structure

All contracts are located in the `src/` directory. `test/btt` contains BTT unit tests for the Auction contracts and associated libraries, and the top level `test/` folder contains additional tests. The suite has unit, fuzz, and invariant tests.

```markdown
src/
----interfaces/
| IContinuousClearingAuction.sol
| IContinuousClearingAuctionFactory.sol
| ...
----libraries/
| ...
----ContinuousClearingAuction.sol
----ContinuousClearingAuctionFactory.sol
test/
----btt/
| auction/
| ...
----Auction.t.sol
----Auction.invariant.t.sol
```

## License

The contracts are covered under the MIT License (`MIT`), see [MIT_LICENSE](https://github.com/Uniswap/continuous-clearing-auction/blob/main/LICENSE).
