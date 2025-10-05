# PermitSingleForwarder
[Git Source](https://github.com/Uniswap/twap-auction/blob/23d1996d53fc32e05713e0f370c3682331c7b03b/src/PermitSingleForwarder.sol)

**Inherits:**
[IPermitSingleForwarder](/src/interfaces/IPermitSingleForwarder.sol/interface.IPermitSingleForwarder.md)

PermitSingleForwarder allows permitting this contract as a spender on permit2

*This contract does not enforce the spender to be this contract, but that is the intended use case*


## State Variables
### PERMIT2
Permit2 address


```solidity
address public constant PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;
```


### permit2
the Permit2 contract to forward approvals


```solidity
IAllowanceTransfer public immutable permit2;
```


## Functions
### constructor


```solidity
constructor(IAllowanceTransfer _permit2);
```

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


