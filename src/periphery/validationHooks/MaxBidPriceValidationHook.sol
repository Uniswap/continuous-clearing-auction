// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IValidationHook} from '../../interfaces/IValidationHook.sol';
import {IValidationHookIntrospection, ValidationHookIntrospection} from './ValidationHookIntrospection.sol';
import {IERC165} from '@openzeppelin/contracts/utils/introspection/IERC165.sol';

/// @title IMaxBidPriceValidationHook
interface IMaxBidPriceValidationHook is IValidationHookIntrospection {
    /// @notice The maximum bid price allowed for a continuous clearing auction
    /// @dev A value of 0 means no effective cap: implementations MUST treat it as "unset" and accept
    ///      every bid price. A literal cap of 0 is unreachable anyway, since a bid must price strictly
    ///      above the clearing price, which starts at a floor of at least `ConstantsLib.MIN_FLOOR_PRICE`.
    /// @return the max bid price allowed, in Q96 form, or 0 for no cap
    function maxBidPrice() external view returns (uint256);
}

/// @title MaxBidPriceValidationHook
/// @notice Validation hook for enforcing a maximum bid price on a continuous clearing auction
/// @dev Since CCA requires all bids to be strictly above the current clearing price, using this hook
///      will prevent new bids from being placed once the maximum bid price is reached. All existing
///      bids will remain active and partially fill for the remaining supply of tokens.
/// @dev Constructing with `_maxBidPrice = 0` disables the cap rather than rejecting every bid.
contract MaxBidPriceValidationHook is IMaxBidPriceValidationHook, ValidationHookIntrospection {
    uint256 public immutable maxBidPrice;

    /// @notice Error thrown when the bid price exceeds the maximum bid price
    error MaxBidPriceExceeded();

    constructor(uint256 _maxBidPrice) {
        maxBidPrice = _maxBidPrice;
    }

    /// @inheritdoc IValidationHook
    function validate(uint256 maxPrice, uint128, address, address, bytes calldata) external view {
        if (maxBidPrice != 0 && maxPrice > maxBidPrice) revert MaxBidPriceExceeded();
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
