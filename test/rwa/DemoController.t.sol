// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ContinuousClearingAuctionFactory} from '../../src/ContinuousClearingAuctionFactory.sol';
import {IContinuousClearingAuction} from '../../src/interfaces/IContinuousClearingAuction.sol';
import {FixedPoint96} from '../../src/libraries/FixedPoint96.sol';
import {RWALauncher} from '../../src/rwa/RWALauncher.sol';
import {RWALauncherFactory} from '../../src/rwa/RWALauncherFactory.sol';
import {Stage} from '../../src/rwa/interfaces/IRWALauncher.sol';
import {DemoController} from '../../demo/contracts/DemoController.sol';
import {DemoERC20} from '../../demo/contracts/DemoERC20.sol';
import {MockTokenMinter} from './mocks/MockTokenMinter.sol';
import {Test} from 'forge-std/Test.sol';
import {DeployPermit2} from 'permit2/test/utils/DeployPermit2.sol';
import {PoolManager} from 'v4-periphery/lib/v4-core/src/PoolManager.sol';

contract DemoControllerTest is Test {
    uint256 internal constant Q96 = FixedPoint96.Q96;

    DemoERC20 internal usdc;
    DemoERC20 internal qqq;
    DemoERC20 internal ant;
    MockTokenMinter internal minterQ;
    MockTokenMinter internal minterA;
    DemoController internal controller;

    address internal issuer = makeAddr('issuer');
    address internal alice = makeAddr('alice');
    address internal bob = makeAddr('bob');

    function setUp() public {
        new DeployPermit2().deployPermit2();
        vm.roll(1_000);
        vm.warp(1_000_000);

        usdc = new DemoERC20('Demo USD Coin', 'dUSDC', 18, 100_000e18);
        qqq = new DemoERC20('Demo QQQ', 'dQQQ', 18, 0);
        ant = new DemoERC20('Demo Anthropic', 'dANT', 18, 0);

        // Realistic-ish prices: 1 QQQ = 500 USDC, 1 Anthropic = 150 USDC (same decimals -> priceQ96 = price*Q96).
        minterQ = new MockTokenMinter(address(usdc), address(qqq), 500 * Q96);
        minterA = new MockTokenMinter(address(usdc), address(ant), 150 * Q96);
        qqq.setMinter(address(minterQ), true);
        ant.setMinter(address(minterA), true);

        PoolManager pm = new PoolManager(address(this));
        ContinuousClearingAuctionFactory ccaFactory = new ContinuousClearingAuctionFactory(address(0));
        RWALauncherFactory rwaFactory = new RWALauncherFactory(address(ccaFactory));
        controller = new DemoController(rwaFactory, address(usdc), address(pm), int24(60), uint24(3_000));
    }

    function _approveAndBid(address who, uint128 amount, address auction, uint16 discountBps) internal {
        usdc.mint(who, amount);
        vm.startPrank(who);
        usdc.approve(address(controller), amount);
        controller.bid(auction, amount, controller.priceForDiscount(discountBps));
        vm.stopPrank();
    }

    function test_startAuction_andBid_graduatesAndBuilds() public {
        uint128 deposit = 2_000e18;

        // Issuer starts the auction.
        usdc.mint(issuer, deposit);
        vm.startPrank(issuer);
        usdc.approve(address(controller), deposit);
        address launcher = controller.startAuction(
            deposit, 100, 100, 1_000e18, address(minterQ), address(qqq), address(minterA), address(ant)
        );
        vm.stopPrank();

        IContinuousClearingAuction auction = RWALauncher(launcher).auction();
        assertEq(uint256(RWALauncher(launcher).stage()), uint256(Stage.BIDDING));

        // Two bidders accept a 50bp discount.
        _approveAndBid(alice, 600e18, address(auction), 50);
        _approveAndBid(bob, 600e18, address(auction), 50);

        // Issuer ends the auction (mine past endBlock) and builds.
        vm.roll(block.number + 101);
        RWALauncher(launcher).build();

        assertTrue(auction.isGraduated(), 'graduated');
        assertEq(uint256(RWALauncher(launcher).stage()), uint256(Stage.ACTIVE), 'active');
        assertEq(usdc.balanceOf(issuer), 1_200e18, 'proceeds to issuer');
    }
}
