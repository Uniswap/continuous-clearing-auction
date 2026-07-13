// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC20} from 'solady/tokens/ERC20.sol';

/// @title PositionShare
/// @notice ERC20 representing a fungible, pro-rata claim on an RWA Launcher's multi-range LP position.
/// @dev The full share supply (1 share base unit per base unit of position notional) is minted to the
///      composed auction up front; winners claim shares from the auction and burn them at redemption.
///      Mint and burn are restricted to the launcher that deployed this token. Decimals match the funding
///      currency so that a full-NAV share price is exactly ONE (`2**96`) on the reused CCA price axis.
/// @custom:security-contact security@uniswap.org
contract PositionShare is ERC20 {
    /// @notice The RWA Launcher authorized to mint and burn shares
    address public immutable LAUNCHER;

    uint8 private immutable _DECIMALS;
    string private _name;
    string private _symbol;

    /// @notice Thrown when a caller other than the launcher attempts to mint or burn
    error OnlyLauncher();

    constructor(string memory name_, string memory symbol_, uint8 decimals_) {
        LAUNCHER = msg.sender;
        _name = name_;
        _symbol = symbol_;
        _DECIMALS = decimals_;
    }

    /// @inheritdoc ERC20
    function name() public view override returns (string memory) {
        return _name;
    }

    /// @inheritdoc ERC20
    function symbol() public view override returns (string memory) {
        return _symbol;
    }

    /// @inheritdoc ERC20
    function decimals() public view override returns (uint8) {
        return _DECIMALS;
    }

    /// @notice Mint shares. Callable only by the launcher.
    function mint(address to, uint256 amount) external {
        if (msg.sender != LAUNCHER) revert OnlyLauncher();
        _mint(to, amount);
    }

    /// @notice Burn shares from `from`. Callable only by the launcher (which burns a redeemer's own balance).
    function burn(address from, uint256 amount) external {
        if (msg.sender != LAUNCHER) revert OnlyLauncher();
        _burn(from, amount);
    }
}
