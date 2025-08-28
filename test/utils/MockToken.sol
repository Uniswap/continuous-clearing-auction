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
