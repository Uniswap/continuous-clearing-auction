// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ITokenMinter} from '../../../src/rwa/interfaces/ITokenMinter.sol';
import {FixedPoint96} from '../../../src/libraries/FixedPoint96.sol';
import {MockERC20} from './MockERC20.sol';

/// @notice Test minter that converts funding currency into a mintable mock pool token at a fixed Q96 rate.
/// @dev `priceQ96` is the price of one base unit of `token` in base units of `currency`. Conversion:
///      tokenAmount = currencyAmount * Q96 / priceQ96; currencyAmount = tokenAmount * priceQ96 / Q96.
contract MockTokenMinter is ITokenMinter {
    address public immutable currency;
    address public immutable token;
    uint256 public immutable priceQ96;

    constructor(address _currency, address _token, uint256 _priceQ96) {
        currency = _currency;
        token = _token;
        priceQ96 = _priceQ96;
    }

    function mint(uint256 currencyAmount) external returns (uint256 tokenAmount) {
        MockERC20(currency).transferFrom(msg.sender, address(this), currencyAmount);
        tokenAmount = (currencyAmount * FixedPoint96.Q96) / priceQ96;
        MockERC20(token).mint(msg.sender, tokenAmount);
    }

    function redeem(uint256 tokenAmount) external returns (uint256 currencyAmount) {
        MockERC20(token).transferFrom(msg.sender, address(this), tokenAmount);
        currencyAmount = (tokenAmount * priceQ96) / FixedPoint96.Q96;
        // Return previously-deposited currency held by this minter.
        MockERC20(currency).transfer(msg.sender, currencyAmount);
    }
}
