# Continuous Clearing Auction

This repository contains the smart contracts for Continuous Clearing Auctions (CCAs). It is intended to be used in combination with the [Uniswap Liquidity Launcher](https://github.com/Uniswap/liquidity-launcher) contracts suite.

## Table of Contents

- [Installation](#installation)
- [Deployments](#deployments)
- [Validation Hooks](#validation-hooks)
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

CCA instances are deployed via the [ContinuousClearingAuctionFactory](./src/ContinuousClearingAuctionFactory.sol). Each factory is bound to a single immutable [IProtocolFeeController](./lib/liquidity-launcher/src/interfaces/IProtocolFeeController.sol) which all auctions it creates use to compute and route protocol fees. Deploy a new factory to use a different fee controller.

Addresses are cannonical across select EVM chains. If it is not already deployed, it can be deployed by anyone following the [Deployment Guide](./docs/DeploymentGuide.md).

### ContinuousClearingAuctionFactory

| Version  | Address                                    | Commit Hash                              | Version          |
| -------- | ------------------------------------------ | ---------------------------------------- | ---------------- |
| v2.0.0   | 0x00cCa200BF124dBfA848937c553864f4B4CE0632 | aee9bca51c92c24eb24a00d75ad98e678bac61d3 | v2.0.0           |
| v1.1.0   | 0xCCccCcCAE7503Cac057829BF2811De42E16e0bD5 | 8508f332c3daf330b189290b335fd9da4e95f3f0 | v1.1.0           |
| v1.0.0\* | 0x0000ccaDF55C911a2FbC0BB9d2942Aa77c6FAa1D | 154fd189022858707837112943c09346869c964f | v1.0.0-candidate |

> \*v2.0.0 is the latest version of CCA and is the recommended version for production use. For more details, see the [Changelog](./CHANGELOG.md).

### CCALens

[CCALens](./src/lens/CCALens.sol) is a stateless periphery contract for offchain reads of auction state and initialized tick data. It is deployed separately from the factory and is safe to share across all auctions on a chain.

| Version | Address                                    | Commit Hash                              | Tag    |
| ------- | ------------------------------------------ | ---------------------------------------- | ------ |
| v2.0.0  | 0xc3C65F5453A3674aDb693cbdA3C842545cD30f53 | aee9bca51c92c24eb24a00d75ad98e678bac61d3 | v2.0.0 |

## Validation Hooks

Auction creators can restrict bidding by setting an optional validation hook at auction creation. On every bid submission the auction calls the hook's [IValidationHook](./src/interfaces/IValidationHook.sol) `validate` function before accepting the bid; hooks MUST revert to signal that a bid is invalid. Per [CIP-1](./CIPs/cip-1.md), hooks should also implement [ERC165](https://eips.ethereum.org/EIPS/eip-165) so that onchain contracts and offchain interfaces can trustlessly discover which interfaces a hook supports via `supportsInterface`. Example hooks are provided in [`src/periphery/validationHooks`](./src/periphery/validationHooks). See [Validation Hooks](./docs/TechnicalDocumentation.md#validation-hooks) in the technical documentation for a guide on writing your own hook and the list of ERC165 interface IDs.

## Audits

The code has been audited by Spearbit, OpenZeppelin, and ABDK Consulting. The most recent audits for v2.0.0 are linked below. For a full list of audits, see [Audits](./docs/audits/README.md).

| Version | Date       | Report                                                |
| ------- | ---------- | ----------------------------------------------------- |
| v2.0.0  | 06/16/2026 | [OpenZeppelin](./docs/audits/OpenZeppelin_v2.0.0.pdf) |
| v2.0.0  | 06/16/2026 | [Spearbit](./docs/audits/Spearbit_v2.0.0.pdf)         |

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
----lens/
| CCALens.sol
| ...
----libraries/
| ...
----periphery/
| validationHooks/
----ContinuousClearingAuction.sol
----ContinuousClearingAuctionFactory.sol
----AuctionStorage.sol
test/
----btt/
| auction/
| ...
----Auction.t.sol
----Auction.invariant.t.sol
```

## License

The contracts are covered under the MIT License (`MIT`), see [MIT_LICENSE](https://github.com/Uniswap/continuous-clearing-auction/blob/main/LICENSE).
