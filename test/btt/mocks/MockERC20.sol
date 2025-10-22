// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import {ERC20} from 'solady/tokens/ERC20.sol';

contract MockERC20 is ERC20 {
    constructor() ERC20() {}

    function name() public pure override returns (string memory) {
        return 'MockERC20';
    }

    function symbol() public pure override returns (string memory) {
        return 'MCK';
    }
}
