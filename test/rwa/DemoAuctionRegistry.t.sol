// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {FixedPoint96} from '../../src/libraries/FixedPoint96.sol';
import {DemoAuctionRegistry} from '../../demo/contracts/DemoAuctionRegistry.sol';
import {DemoLaunchpad} from '../../demo/contracts/DemoLaunchpad.sol';
import {DemoERC20} from '../../demo/contracts/DemoERC20.sol';
import {MockTokenMinter} from './mocks/MockTokenMinter.sol';
import {Test} from 'forge-std/Test.sol';
import {PoolManager} from 'v4-periphery/lib/v4-core/src/PoolManager.sol';

contract DemoAuctionRegistryTest is Test {
    uint256 internal constant Q96 = FixedPoint96.Q96;
    uint128 internal constant DEPOSIT = 2_000e18;

    DemoERC20 internal usdc;
    DemoERC20 internal qqq;
    DemoERC20 internal ant;
    DemoAuctionRegistry internal registry;
    address internal creator = makeAddr('creator');

    function setUp() public {
        usdc = new DemoERC20('Demo USD Coin', 'dUSDC', 18, 1_000_000e18);
        qqq = new DemoERC20('Demo QQQ', 'dQQQ', 18, 0);
        ant = new DemoERC20('Demo Anthropic', 'dANT', 18, 0);
        MockTokenMinter minterQ = new MockTokenMinter(address(usdc), address(qqq), 500 * Q96);
        MockTokenMinter minterA = new MockTokenMinter(address(usdc), address(ant), 150 * Q96);
        qqq.setMinter(address(minterQ), true);
        ant.setMinter(address(minterA), true);
        PoolManager pm = new PoolManager(address(this));
        registry = new DemoAuctionRegistry(
            address(usdc), address(qqq), address(ant), address(minterQ), address(minterA), address(pm), int24(60), DEPOSIT, 100
        );
    }

    function _create(address who) internal returns (address) {
        usdc.mint(who, DEPOSIT);
        vm.startPrank(who);
        usdc.approve(address(registry), DEPOSIT);
        address a = registry.createAndRegister();
        vm.stopPrank();
        return a;
    }

    function test_createAndRegister_tracksLatest() public {
        assertEq(registry.latest(), address(0));
        address a1 = _create(creator);
        assertEq(registry.count(), 1);
        assertEq(registry.latest(), a1);
        assertTrue(DemoLaunchpad(a1).started(), 'started');
        assertEq(DemoLaunchpad(a1).ISSUER(), creator, 'issuer is creator');

        // Anyone can reset -> a new auction becomes latest.
        address a2 = _create(makeAddr('other'));
        assertEq(registry.count(), 2);
        assertEq(registry.latest(), a2);
        assertTrue(a2 != a1, 'distinct auctions');
        // Distinct pool fees keep pool ids unique across rounds.
        assertTrue(DemoLaunchpad(a1).poolId() != DemoLaunchpad(a2).poolId(), 'distinct pools');
    }
}
