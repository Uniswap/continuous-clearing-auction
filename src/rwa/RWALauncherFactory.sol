// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IContinuousClearingAuctionFactory} from '../interfaces/IContinuousClearingAuctionFactory.sol';
import {RWALauncher} from './RWALauncher.sol';
import {RWALauncherParameters} from './interfaces/IRWALauncher.sol';
import {ActionConstants} from 'v4-periphery/src/libraries/ActionConstants.sol';

/// @title RWALauncherFactory
/// @notice Deploys {RWALauncher} instances bound to a single CCA factory (which fixes the protocol fee
///         controller used by every composed auction). Deploy a new factory to use a different CCA factory.
/// @custom:security-contact security@uniswap.org
contract RWALauncherFactory {
    /// @notice The CCA factory each launcher uses to deploy its composed auction
    IContinuousClearingAuctionFactory public immutable CCA_FACTORY;

    /// @notice Emitted when a launcher is created
    event LauncherCreated(address indexed launcher, address indexed currency, uint128 deposit);

    error InvalidDepositAmount(uint256 amount);

    constructor(address ccaFactory) {
        CCA_FACTORY = IContinuousClearingAuctionFactory(ccaFactory);
    }

    /// @notice Create a new RWA Launcher.
    /// @dev Push model, mirroring {IDistributorFactory}: `token` is the funding currency and `amount` is the
    ///      issuer deposit `D`. The issuer transfers `amount` of `token` to the returned launcher, then calls
    ///      `onTokensReceived()`. `fundsRecipient`/`sharesRecipient` set to `ActionConstants.MSG_SENDER`
    ///      resolve to the caller.
    /// @param amount The issuer deposit (funding-currency base units); equals the share supply
    /// @param configData ABI-encoded {RWALauncherParameters}
    /// @param salt Caller-supplied salt for the deterministic address
    function create(address, /*token*/ uint256 amount, bytes calldata configData, bytes32 salt)
        external
        returns (address launcher)
    {
        if (amount > type(uint128).max) revert InvalidDepositAmount(amount);
        RWALauncherParameters memory p = abi.decode(configData, (RWALauncherParameters));
        if (p.fundsRecipient == ActionConstants.MSG_SENDER) p.fundsRecipient = msg.sender;
        if (p.sharesRecipient == ActionConstants.MSG_SENDER) p.sharesRecipient = msg.sender;

        launcher = address(new RWALauncher{salt: keccak256(abi.encode(msg.sender, salt))}(uint128(amount), p, CCA_FACTORY));
        emit LauncherCreated(launcher, p.currency, uint128(amount));
    }
}
