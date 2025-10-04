# IPermitSingleForwarder
[Git Source](https://github.com/Uniswap/twap-auction/blob/eddb06d9f9e6a95363d90d7326e355d98c8b0712/src/interfaces/IPermitSingleForwarder.sol)

Interface for the PermitSingleForwarder contract


## Functions
### permit

allows forwarding a single permit to permit2

*this function is payable to allow multicall with NATIVE based actions*


```solidity
function permit(address owner, IAllowanceTransfer.PermitSingle calldata permitSingle, bytes calldata signature)
    external
    payable
    returns (bytes memory err);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`owner`|`address`|the owner of the tokens|
|`permitSingle`|`IAllowanceTransfer.PermitSingle`|the permit data|
|`signature`|`bytes`|the signature of the permit; abi.encodePacked(r, s, v)|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`err`|`bytes`|the error returned by a reverting permit call, empty if successful|


