// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ERC20Mock} from 'openzeppelin-contracts/contracts/mocks/token/ERC20Mock.sol';

/// @notice Handler contract for setting up tokens
abstract contract TokenHandler {
    ERC20Mock public token;
    ERC20Mock public erc20Currency;
    address public constant ETH_SENTINEL = address(0);

    function setUpTokens() public {
        token = new ERC20Mock();
        erc20Currency = new ERC20Mock();
    }
}
