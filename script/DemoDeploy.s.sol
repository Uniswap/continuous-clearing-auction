// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ContinuousClearingAuctionFactory} from '../src/ContinuousClearingAuctionFactory.sol';
import {FixedPoint96} from '../src/libraries/FixedPoint96.sol';
import {RWALauncherFactory} from '../src/rwa/RWALauncherFactory.sol';
import {DemoController} from '../demo/contracts/DemoController.sol';
import {DemoERC20} from '../demo/contracts/DemoERC20.sol';
import {MockTokenMinter} from '../test/rwa/mocks/MockTokenMinter.sol';
import {Script} from 'forge-std/Script.sol';
import {PoolManager} from 'v4-periphery/lib/v4-core/src/PoolManager.sol';

/// @notice Deploys the full RWA Launcher demo stack to a local chain and writes addresses to
///         demo/web/addresses.json for the UI. Run against anvil:
///   anvil & forge script script/DemoDeploy.s.sol --rpc-url http://127.0.0.1:8545 --broadcast
contract DemoDeploy is Script {
    // anvil default account 0
    uint256 internal constant DEFAULT_PK = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;
    uint256 internal constant Q96 = FixedPoint96.Q96;

    function run() external {
        uint256 pk = vm.envOr('PRIVATE_KEY', DEFAULT_PK);
        vm.startBroadcast(pk);

        // Dummy tokens. USDC is faucetable by anyone; QQQ/ANT are minted by their minters.
        DemoERC20 usdc = new DemoERC20('Demo USD Coin', 'dUSDC', 18, 1_000_000e18);
        DemoERC20 qqq = new DemoERC20('Demo QQQ', 'dQQQ', 18, 0);
        DemoERC20 ant = new DemoERC20('Demo Anthropic', 'dANT', 18, 0);

        // Per-side minters: 1 QQQ = 500 dUSDC, 1 Anthropic = 150 dUSDC.
        MockTokenMinter minterQ = new MockTokenMinter(address(usdc), address(qqq), 500 * Q96);
        MockTokenMinter minterA = new MockTokenMinter(address(usdc), address(ant), 150 * Q96);
        qqq.setMinter(address(minterQ), true);
        ant.setMinter(address(minterA), true);

        // Core stack.
        PoolManager poolManager = new PoolManager(msg.sender);
        ContinuousClearingAuctionFactory ccaFactory = new ContinuousClearingAuctionFactory(address(0));
        RWALauncherFactory rwaFactory = new RWALauncherFactory(address(ccaFactory));
        DemoController controller =
            new DemoController(rwaFactory, address(usdc), address(poolManager), int24(60), uint24(3_000));

        vm.stopBroadcast();

        // Write addresses for the UI.
        string memory o = 'demo';
        vm.serializeUint(o, 'chainId', block.chainid);
        vm.serializeAddress(o, 'usdc', address(usdc));
        vm.serializeAddress(o, 'qqq', address(qqq));
        vm.serializeAddress(o, 'ant', address(ant));
        vm.serializeAddress(o, 'minterQ', address(minterQ));
        vm.serializeAddress(o, 'minterA', address(minterA));
        vm.serializeAddress(o, 'poolManager', address(poolManager));
        vm.serializeAddress(o, 'ccaFactory', address(ccaFactory));
        vm.serializeAddress(o, 'rwaFactory', address(rwaFactory));
        vm.serializeUint(o, 'qqqPriceUsd', 500);
        vm.serializeUint(o, 'antPriceUsd', 150);
        string memory out = vm.serializeAddress(o, 'controller', address(controller));
        vm.writeJson(out, 'demo/web/addresses.json');
    }
}
