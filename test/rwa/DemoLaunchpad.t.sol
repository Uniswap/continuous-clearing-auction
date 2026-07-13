// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {FixedPoint96} from '../../src/libraries/FixedPoint96.sol';
import {PositionShare} from '../../src/rwa/PositionShare.sol';
import {DemoLaunchpad} from '../../demo/contracts/DemoLaunchpad.sol';
import {DemoERC20} from '../../demo/contracts/DemoERC20.sol';
import {MockTokenMinter} from './mocks/MockTokenMinter.sol';
import {Test} from 'forge-std/Test.sol';
import {PoolManager} from 'v4-periphery/lib/v4-core/src/PoolManager.sol';

contract DemoLaunchpadTest is Test {
    uint256 internal constant Q96 = FixedPoint96.Q96;

    DemoERC20 internal usdc;
    DemoERC20 internal qqq;
    DemoERC20 internal ant;
    MockTokenMinter internal minterQ;
    MockTokenMinter internal minterA;
    PoolManager internal pm;
    DemoLaunchpad internal pad;

    address internal issuer = address(this);
    address internal alice = makeAddr('alice');
    address internal bob = makeAddr('bob');
    address internal randomEnder = makeAddr('randomEnder');

    uint128 internal constant DEPOSIT = 2_000e18;

    function setUp() public {
        usdc = new DemoERC20('Demo USD Coin', 'dUSDC', 18, 1_000_000e18);
        qqq = new DemoERC20('Demo QQQ', 'dQQQ', 18, 0);
        ant = new DemoERC20('Demo Anthropic', 'dANT', 18, 0);
        minterQ = new MockTokenMinter(address(usdc), address(qqq), 500 * Q96);
        minterA = new MockTokenMinter(address(usdc), address(ant), 150 * Q96);
        qqq.setMinter(address(minterQ), true);
        ant.setMinter(address(minterA), true);
        pm = new PoolManager(address(this));

        pad = new DemoLaunchpad(
            issuer, address(usdc), DEPOSIT, 100, address(minterQ), address(qqq), address(minterA), address(ant),
            address(pm), int24(60), uint24(3_000)
        );

        // Issuer funds the deposit and opens bidding.
        usdc.mint(address(this), DEPOSIT);
        usdc.transfer(address(pad), DEPOSIT);
        pad.start();
    }

    function _bid(address who, uint128 amount, uint16 discount) internal {
        usdc.mint(who, amount);
        vm.startPrank(who);
        usdc.approve(address(pad), amount);
        pad.bid(amount, discount);
        vm.stopPrank();
    }

    function test_anyoneCanEnd_permissionless() public {
        _bid(alice, 600e18, 50);
        _bid(bob, 600e18, 50);

        // Undersubscribed (1200 < 2000) -> clears at the floor (100 bps).
        assertEq(pad.clearingDiscount(), 100);

        // A random third party (not issuer, not a bidder) ends the auction.
        uint256 issuerBefore = usdc.balanceOf(issuer);
        vm.prank(randomEnder);
        pad.end();

        assertTrue(pad.ended(), 'ended');
        // Winners pay the clearing (100bp) discount: 1200 * 0.99 = 1188 to issuer.
        assertEq(usdc.balanceOf(issuer) - issuerBefore, 1_188e18, 'proceeds to issuer');
        // Winners receive shares equal to their filled notional.
        assertEq(PositionShare(pad.SHARE()).balanceOf(alice), 600e18, 'alice shares');
        assertEq(PositionShare(pad.SHARE()).balanceOf(bob), 600e18, 'bob shares');
        // Alice was refunded the discount portion: 600 * 1% = 6.
        assertEq(usdc.balanceOf(alice), 6e18, 'alice discount refund');
    }

    function test_end_revertsTwice() public {
        _bid(alice, 600e18, 50);
        pad.end();
        vm.expectRevert(DemoLaunchpad.AlreadyEnded.selector);
        pad.end();
    }

    function test_unwind_and_redeem_permissionless() public {
        _bid(alice, 600e18, 50);
        _bid(bob, 600e18, 50);
        pad.end();

        // Anyone can end the lockup.
        vm.prank(randomEnder);
        pad.unwind();
        assertTrue(pad.unwound(), 'unwound');
        assertGt(pad.pot0(), 0, 'pot0');
        assertGt(pad.pot1(), 0, 'pot1');
        // Total shares == deposit notional (winners + issuer's unsold co-LP stake).
        assertEq(pad.sharesOutstanding(), DEPOSIT, 'shares outstanding == deposit');

        PositionShare share = PositionShare(pad.SHARE());
        uint256 aliceShares = share.balanceOf(alice);
        assertEq(aliceShares, 600e18, 'alice shares');

        vm.prank(alice);
        (uint256 a0, uint256 a1) = pad.redeem(aliceShares);
        assertGt(a0, 0, 'redeemed token0');
        assertGt(a1, 0, 'redeemed token1');
        assertEq(share.balanceOf(alice), 0, 'shares burned');
    }

    function test_oversubscribed_clearingRises() public {
        // 3 bids totaling 3000 > 2000 deposit, at increasing discounts.
        _bid(alice, 1_000e18, 10);
        _bid(bob, 1_000e18, 20);
        _bid(makeAddr('carol'), 1_000e18, 80);
        // Fill 2000 from lowest discount up: 1000@10 + 1000@20 = 2000 -> clears at 20 bps.
        assertEq(pad.clearingDiscount(), 20);
    }
}
