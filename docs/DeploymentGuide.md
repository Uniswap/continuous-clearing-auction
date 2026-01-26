# Deployment Guide

Continuous Clearing Auction instances are deployed via Factory pattern. The factory contract has no parameters and can be deployed to the same address across all compatible EVM chains.

## Factory Deployment
The Factory contract can be deployed via the [DeployContinuousAuctionFactoryScript](../script/deploy/DeployContinuousAuctionFactory.s.sol). It deploys to the same address where the foundry CREATE2 deployer is deployed.

```bash
forge script script/deploy/DeployContinuousAuctionFactory.s.sol:DeployContinuousAuctionFactoryScript --rpc-url <rpc_url> --broadcast --private-key <private_key>
```

## Deploying via Factory
The Factory contract has a simple interface (from [IContinuousClearingAuctionFactory.sol](./src/interfaces/IContinuousClearingAuctionFactory.sol)):
```solidity
/// From IContinuousClearingAuctionFactory.sol
{
    function initializeDistribution(address token, uint256 amount, bytes calldata configData, bytes32 salt)
        external
        returns (IDistributionContract distributionContract);

    function getAuctionAddress(address token, uint256 amount, bytes calldata configData, bytes32 salt, address sender)
        external
        view
        returns (address);
}
```

Call `initializeDistribution` to deploy a new auction instance, providing the `token`, `amount`, `configData`, and `salt` parameters.

- `token` is the address of the token to be sold.
- `amount` is the amount of tokens to sell in the auction
- `configData` is the abi-encoded [AuctionParameters](./src/interfaces/IContinuousClearingAuction.sol) struct
- `salt` is an optional bytes32 value for vanity address mining

The function will return the address of the new auction instance.

## Deploying via Constructor
Alternatively, you can deploy the auction instance directly via the constructor.

```solidity
/// From ContinuousClearingAuction.sol
{
    constructor(address token, uint128 amount, AuctionParameters memory parameters) {
        // ...
    }
}
```

The parameters are the same but the constructor does not require a `salt` parameter.

## Post deployment
Integrating contracts should call `IDistributionContract.onTokensReceived` to notify the auction that the tokens have been received. If deploying from an EOA, this can be done by calling the function directly on the auction instance.

This is a required pre-requisite before the auction can begin accepting bids.

## Block explorer verification
Newly deployed auctions may require manual verification on block explorers. The easiest way to do this is to run the following shell script which will write the standard json input to a new file:

```bash
forge verify-contract <address> src/ContinuousClearingAuction.sol:ContinuousClearingAuction --rpc-url <rpc_url> --show-standard-json-input > standard-json-input.json
```

Most block explorers will support uploading this file to verify the contract.