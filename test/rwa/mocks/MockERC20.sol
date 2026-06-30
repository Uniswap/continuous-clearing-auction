// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC20} from 'solady/tokens/ERC20.sol';

/// @notice Minimal mintable/burnable ERC20 with configurable decimals for RWA Launcher tests.
contract MockERC20 is ERC20 {
    string private _name;
    string private _symbol;
    uint8 private immutable _decimals;

    constructor(string memory n, string memory s, uint8 d) {
        _name = n;
        _symbol = s;
        _decimals = d;
    }

    function name() public view override returns (string memory) {
        return _name;
    }

    function symbol() public view override returns (string memory) {
        return _symbol;
    }

    function decimals() public view override returns (uint8) {
        return _decimals;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) external {
        _burn(from, amount);
    }
}
