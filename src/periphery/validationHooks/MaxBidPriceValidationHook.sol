// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IValidationHook} from '../../interfaces/IValidationHook.sol';
import {IValidationHookIntrospection, ValidationHookIntrospection} from './ValidationHookIntrospection.sol';
import {IERC165} from '@openzeppelin/contracts/utils/introspection/IERC165.sol';

/// @title IMaxBidPriceValidationHook
interface IMaxBidPriceValidationHook is IValidationHookIntrospection {
    /// @notice The maximum bid price allowed for a continuous clearing auction
    /// @return the max bid price allowed, in Q96 form
    function maxBidPrice() external view returns (uint256);
}

/// @title MaxBidPriceValidationHook
/// @notice Validation hook for enforcing a maximum bid price on a continuous clearing auction
/// @dev Since CCA requires all bids to be strictly above the current clearing price, using this hook
///      will prevent new bids from being placed once the maximum bid price is reached. All existing
///      bids will remain active and partially fill for the remaining supply of tokens.
contract MaxBidPriceValidationHook is IMaxBidPriceValidationHook, ValidationHookIntrospection {
    uint256 public immutable maxBidPrice;

    /// @notice Error thrown when the bid price exceeds the maximum bid price
    error MaxBidPriceExceeded();

    constructor(uint256 _maxBidPrice) {
        maxBidPrice = _maxBidPrice;
    }

    /// @inheritdoc IValidationHook
    function validate(uint256 maxPrice, uint128, address, address, bytes calldata) external view {
        if (maxPrice > maxBidPrice) revert MaxBidPriceExceeded();
    }

    /// @inheritdoc IERC165
    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ValidationHookIntrospection, IERC165)
        returns (bool)
    {
        return super.supportsInterface(interfaceId) || interfaceId == type(IMaxBidPriceValidationHook).interfaceId;
    }
}
