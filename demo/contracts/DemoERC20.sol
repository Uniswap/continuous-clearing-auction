// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC20} from 'solady/tokens/ERC20.sol';

/// @title DemoERC20
/// @notice Test/demo ERC20 with an open faucet and owner-managed minters.
/// @dev NOT for production. `faucet()` lets anyone mint themselves test funds (e.g. demo USDC); `mint()` is
///      restricted to the owner and authorized minters (e.g. the RWA Launcher's per-side token minters).
contract DemoERC20 is ERC20 {
    string private _name;
    string private _symbol;
    uint8 private immutable _decimals;

    /// @notice Amount minted per `faucet()` call
    uint256 public immutable FAUCET_AMOUNT;
    /// @notice The owner that can authorize minters
    address public owner;
    /// @notice Addresses allowed to call `mint`
    mapping(address => bool) public isMinter;

    error NotOwner();
    error NotMinter();

    event MinterSet(address indexed minter, bool allowed);

    constructor(string memory name_, string memory symbol_, uint8 decimals_, uint256 faucetAmount_) {
        _name = name_;
        _symbol = symbol_;
        _decimals = decimals_;
        FAUCET_AMOUNT = faucetAmount_;
        owner = msg.sender;
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

    /// @notice Authorize or revoke a minter. Owner only.
    function setMinter(address minter, bool allowed) external {
        if (msg.sender != owner) revert NotOwner();
        isMinter[minter] = allowed;
        emit MinterSet(minter, allowed);
    }

    /// @notice Mint `amount` to `to`. Owner or an authorized minter only.
    function mint(address to, uint256 amount) external {
        if (msg.sender != owner && !isMinter[msg.sender]) revert NotMinter();
        _mint(to, amount);
    }

    /// @notice Mint the fixed faucet amount to the caller. Open to anyone (demo only).
    function faucet() external {
        _mint(msg.sender, FAUCET_AMOUNT);
    }
}
