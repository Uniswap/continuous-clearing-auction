// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {DemoAuctionRegistry} from '../demo/contracts/DemoAuctionRegistry.sol';
import {DemoERC20} from '../demo/contracts/DemoERC20.sol';
import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {Script} from 'forge-std/Script.sol';

/// @notice Deploys the DemoAuctionRegistry (reusing the shared test tokens/minters/PoolManager from
///         demo/web/addresses.json), creates the first auction, and writes the registry address for the UI.
///   PRIVATE_KEY=0x.. POOL_MANAGER=0x.. forge script script/DemoRegistryDeploy.s.sol --rpc-url $RPC --broadcast
contract DemoRegistryDeploy is Script {
    uint256 internal constant ONE = 1e18;

    function run() external {
        string memory j = vm.readFile('demo/web/addresses.json');
        address usdc = vm.parseJsonAddress(j, '.usdc');
        address qqq = vm.parseJsonAddress(j, '.qqq');
        address ant = vm.parseJsonAddress(j, '.ant');
        address minterQ = vm.parseJsonAddress(j, '.minterQ');
        address minterA = vm.parseJsonAddress(j, '.minterA');
        address poolManager = vm.envOr('POOL_MANAGER', vm.parseJsonAddress(j, '.poolManager'));

        uint256 pk = vm.envUint('PRIVATE_KEY');
        uint128 deposit = uint128(vm.envOr('DEPOSIT', uint256(2_000)) * ONE);
        uint16 maxDiscountBps = uint16(vm.envOr('MAX_DISCOUNT_BPS', uint256(100)));

        vm.startBroadcast(pk);
        DemoAuctionRegistry registry =
            new DemoAuctionRegistry(usdc, qqq, ant, minterQ, minterA, poolManager, int24(60), deposit, maxDiscountBps);
        // Seed the first auction.
        DemoERC20(usdc).faucet();
        IERC20(usdc).approve(address(registry), type(uint256).max);
        registry.createAndRegister();
        vm.stopBroadcast();

        string memory o = 'demo';
        vm.serializeUint(o, 'chainId', vm.parseJsonUint(j, '.chainId'));
        vm.serializeAddress(o, 'usdc', usdc);
        vm.serializeAddress(o, 'qqq', qqq);
        vm.serializeAddress(o, 'ant', ant);
        vm.serializeAddress(o, 'minterQ', minterQ);
        vm.serializeAddress(o, 'minterA', minterA);
        vm.serializeAddress(o, 'poolManager', poolManager);
        vm.serializeAddress(o, 'registry', address(registry));
        vm.serializeUint(o, 'maxDiscountBps', uint256(maxDiscountBps));
        vm.serializeUint(o, 'qqqPriceUsd', vm.parseJsonUint(j, '.qqqPriceUsd'));
        vm.serializeUint(o, 'antPriceUsd', vm.parseJsonUint(j, '.antPriceUsd'));
        string memory out = vm.serializeAddress(o, 'issuer', vm.addr(pk));
        vm.writeJson(out, 'demo/web/addresses.json');
    }
}
