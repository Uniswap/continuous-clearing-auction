// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {DemoLaunchpad} from '../demo/contracts/DemoLaunchpad.sol';
import {DemoERC20} from '../demo/contracts/DemoERC20.sol';
import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {Script} from 'forge-std/Script.sol';
import {IHooks} from 'v4-periphery/lib/v4-core/src/interfaces/IHooks.sol';
import {Currency} from 'v4-periphery/lib/v4-core/src/types/Currency.sol';
import {PoolId, PoolIdLibrary} from 'v4-periphery/lib/v4-core/src/types/PoolId.sol';
import {PoolKey} from 'v4-periphery/lib/v4-core/src/types/PoolKey.sol';

/// @notice Deploys a permissionless-endable DemoLaunchpad, reusing the tokens/minters/PoolManager already
///         deployed by DemoDeployLive (read from demo/web/addresses.json), funds the deposit, and opens
///         bidding. Anyone can then call end() at any time to settle. Rewrites addresses.json for the UI.
///   PRIVATE_KEY=0x.. forge script script/DemoLaunchpadDeploy.s.sol --rpc-url $RPC --broadcast
contract DemoLaunchpadDeploy is Script {
    uint256 internal constant ONE = 1e18;

    function run() external {
        string memory j = vm.readFile('demo/web/addresses.json');
        address usdc = vm.parseJsonAddress(j, '.usdc');
        address qqq = vm.parseJsonAddress(j, '.qqq');
        address ant = vm.parseJsonAddress(j, '.ant');
        address minterQ = vm.parseJsonAddress(j, '.minterQ');
        address minterA = vm.parseJsonAddress(j, '.minterA');
        // Use the canonical v4 PoolManager (override via env) so the pool is viewable on the Uniswap interface.
        address poolManager = vm.envOr('POOL_MANAGER', vm.parseJsonAddress(j, '.poolManager'));

        uint256 pk = vm.envUint('PRIVATE_KEY');
        address deployer = vm.addr(pk);
        uint128 deposit = uint128(vm.envOr('DEPOSIT', uint256(2_000)) * ONE);
        uint16 maxDiscountBps = uint16(vm.envOr('MAX_DISCOUNT_BPS', uint256(100)));
        // Distinct pool fee per run keeps the v4 pool key unique so repeated demos can each build.
        uint24 poolFee = uint24(3_000 + (block.number % 50_000));

        vm.startBroadcast(pk);
        DemoLaunchpad pad = new DemoLaunchpad(
            deployer, usdc, deposit, maxDiscountBps, minterQ, qqq, minterA, ant, poolManager, int24(60), poolFee
        );
        DemoERC20(usdc).faucet();
        IERC20(usdc).transfer(address(pad), deposit);
        pad.start();
        vm.stopBroadcast();

        string memory o = 'demo';
        vm.serializeUint(o, 'chainId', vm.parseJsonUint(j, '.chainId'));
        vm.serializeAddress(o, 'usdc', usdc);
        vm.serializeAddress(o, 'qqq', qqq);
        vm.serializeAddress(o, 'ant', ant);
        vm.serializeAddress(o, 'minterQ', minterQ);
        vm.serializeAddress(o, 'minterA', minterA);
        vm.serializeAddress(o, 'poolManager', poolManager);
        vm.serializeAddress(o, 'launchpad', address(pad));
        // Deterministic v4 poolId for the pool end() will create, so the UI can link to it on Uniswap.
        (Currency c0, Currency c1) = qqq < ant
            ? (Currency.wrap(qqq), Currency.wrap(ant))
            : (Currency.wrap(ant), Currency.wrap(qqq));
        PoolId poolId = PoolIdLibrary.toId(
            PoolKey({currency0: c0, currency1: c1, fee: poolFee, tickSpacing: int24(60), hooks: IHooks(address(0))})
        );
        vm.serializeBytes32(o, 'poolId', PoolId.unwrap(poolId));
        vm.serializeUint(o, 'poolFee', uint256(poolFee));
        vm.serializeUint(o, 'startBlock', block.number);
        vm.serializeUint(o, 'maxDiscountBps', uint256(maxDiscountBps));
        vm.serializeUint(o, 'qqqPriceUsd', vm.parseJsonUint(j, '.qqqPriceUsd'));
        vm.serializeUint(o, 'antPriceUsd', vm.parseJsonUint(j, '.antPriceUsd'));
        string memory out = vm.serializeAddress(o, 'issuer', deployer);
        vm.writeJson(out, 'demo/web/addresses.json');
    }
}
