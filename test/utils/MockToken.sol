// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC20ReturnFalseMock} from 'openzeppelin-contracts/contracts/mocks/token/ERC20ReturnFalseMock.sol';
import {ERC20} from 'openzeppelin-contracts/contracts/token/ERC20/ERC20.sol';

contract MockToken is ERC20ReturnFalseMock {
    constructor() ERC20('MockFailingToken', 'FAIL') {}

    function mint(address account, uint256 amount) external {
        _mint(account, amount);
    }
}

contract WorkingCustomMockToken is ERC20 {
    uint8 private _decimals;

    constructor(string memory name, string memory symbol, uint8 decimals_, uint256 initialSupply) ERC20(name, symbol) {
        _decimals = decimals_;
        _mint(msg.sender, initialSupply);
    }

    function decimals() public view virtual override returns (uint8) {
        return _decimals;
    }

    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }
}
