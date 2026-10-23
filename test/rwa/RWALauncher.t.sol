// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ContinuousClearingAuctionFactory} from '../../src/ContinuousClearingAuctionFactory.sol';
import {IContinuousClearingAuction} from '../../src/interfaces/IContinuousClearingAuction.sol';
import {ConstantsLib} from '../../src/libraries/ConstantsLib.sol';
import {FixedPoint96} from '../../src/libraries/FixedPoint96.sol';
import {RWALauncher} from '../../src/rwa/RWALauncher.sol';
import {RWALauncherFactory} from '../../src/rwa/RWALauncherFactory.sol';
import {
    IRWALauncher, RWALauncherParameters, SideConfig, TrancheConfig, Stage
} from '../../src/rwa/interfaces/IRWALauncher.sol';
import {AuctionStepsBuilder} from '../utils/AuctionStepsBuilder.sol';
import {MockERC20} from './mocks/MockERC20.sol';
import {MockTokenMinter} from './mocks/MockTokenMinter.sol';
import {Test} from 'forge-std/Test.sol';
import {IAllowanceTransfer} from 'permit2/src/interfaces/IAllowanceTransfer.sol';
import {DeployPermit2} from 'permit2/test/utils/DeployPermit2.sol';
import {PoolManager} from 'v4-periphery/lib/v4-core/src/PoolManager.sol';

contract RWALauncherTest is Test {
    using AuctionStepsBuilder for bytes;

    address internal constant PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;
    uint256 internal constant Q96 = FixedPoint96.Q96;

    uint128 internal constant DEPOSIT = 2_000e18; // issuer deposit / share supply
    uint64 internal constant DURATION = 100;
    uint16 internal constant MAX_DISCOUNT_BPS = 100; // 1%
    uint128 internal constant REQUIRED_SHARES = 1_000e18;

    MockERC20 internal currency; // funding currency (e.g. USDC)
    MockERC20 internal tokenA; // pool token (e.g. QQQ)
    MockERC20 internal tokenB; // pool token (e.g. Anthropic)
    MockTokenMinter internal minterA;
    MockTokenMinter internal minterB;
    PoolManager internal poolManager;
    ContinuousClearingAuctionFactory internal ccaFactory;
    RWALauncherFactory internal factory;

    RWALauncher internal launcher;
    IContinuousClearingAuction internal auction;

    address internal issuer = makeAddr('issuer');
    address internal alice = makeAddr('alice');
    address internal bob = makeAddr('bob');

    uint256 internal startBlock;
    uint256 internal tickSpacing;
    uint256 internal floorPrice;

    function setUp() public {
        new DeployPermit2().deployPermit2();
        vm.roll(1_000);
        vm.warp(1_000_000);

        currency = new MockERC20('USD Coin', 'USDC', 18);
        tokenA = new MockERC20('QQQ', 'QQQ', 18);
        tokenB = new MockERC20('Anthropic', 'ANT', 18);
        // 1:1 base-unit pricing keeps the pool init price at ~1.0 and minted amount == budget.
        minterA = new MockTokenMinter(address(currency), address(tokenA), Q96);
        minterB = new MockTokenMinter(address(currency), address(tokenB), Q96);

        poolManager = new PoolManager(address(this));
        ccaFactory = new ContinuousClearingAuctionFactory(address(0)); // no protocol fee
        factory = new RWALauncherFactory(address(ccaFactory));

        startBlock = block.number;
        tickSpacing = Q96 / 10_000; // 1bp granularity
        floorPrice = (Q96 * (10_000 - MAX_DISCOUNT_BPS)) / 10_000;
        floorPrice = (floorPrice / tickSpacing) * tickSpacing; // rounded to a tick boundary, as the launcher does

        TrancheConfig[] memory tranches = new TrancheConfig[](4);
        tranches[0] = TrancheConfig({rangeWidthBps: 5, weightBps: 1_000});
        tranches[1] = TrancheConfig({rangeWidthBps: 10, weightBps: 2_000});
        tranches[2] = TrancheConfig({rangeWidthBps: 50, weightBps: 3_000});
        tranches[3] = TrancheConfig({rangeWidthBps: 100, weightBps: 4_000});

        RWALauncherParameters memory p = RWALauncherParameters({
            currency: address(currency),
            side0: SideConfig({minter: address(minterA), token: address(tokenA), budgetWeightBps: 5_000}),
            side1: SideConfig({minter: address(minterB), token: address(tokenB), budgetWeightBps: 5_000}),
            fundsRecipient: issuer,
            sharesRecipient: issuer,
            startBlock: uint64(startBlock),
            endBlock: uint64(startBlock + DURATION),
            claimBlock: uint64(startBlock + DURATION + 1),
            lpDuration: 50,
            tickSpacing: tickSpacing,
            maxDiscountBps: MAX_DISCOUNT_BPS,
            requiredSharesSold: REQUIRED_SHARES,
            tranches: tranches,
            validationHook: address(0),
            // per-block mps * blockDelta == MPS (100% of supply issued over the auction)
            auctionStepsData: AuctionStepsBuilder.init().addStep(uint24(ConstantsLib.MPS / DURATION), uint40(DURATION)),
            poolManager: address(poolManager),
            poolTickSpacing: int24(60),
            poolFee: uint24(3_000),
            poolHooks: address(0)
        });

        launcher = RWALauncher(factory.create(address(currency), DEPOSIT, abi.encode(p), bytes32(0)));
        auction = launcher.auction();
    }

    // -- helpers ---------------------------------------------------------------------------------------------

    function _deposit() internal {
        currency.mint(address(launcher), DEPOSIT); // issuer pushes the deposit
        launcher.onTokensReceived();
    }

    function _bid(address who, uint128 amount, uint256 maxPrice) internal returns (uint256 bidId) {
        currency.mint(who, amount);
        vm.startPrank(who);
        currency.approve(PERMIT2, type(uint256).max);
        IAllowanceTransfer(PERMIT2).approve(address(currency), address(auction), uint160(amount), uint48(block.timestamp + 1 days));
        bidId = auction.submitBid(maxPrice, amount, who, bytes(''));
        vm.stopPrank();
    }

    // -- tests -----------------------------------------------------------------------------------------------

    function test_setup_deploysAuctionAndShare() public view {
        assertEq(address(launcher.auction()), address(auction));
        assertEq(auction.currency(), address(currency));
        assertEq(auction.token(), launcher.shareToken());
        assertEq(uint256(launcher.stage()), uint256(Stage.SETUP));
        assertEq(auction.floorPrice(), floorPrice);
    }

    function test_deposit_startsBidding() public {
        _deposit();
        assertEq(uint256(launcher.stage()), uint256(Stage.BIDDING));
        // The full share supply is minted to the auction.
        assertEq(MockERC20(launcher.shareToken()).balanceOf(address(auction)), DEPOSIT);
    }

    function test_build_revertsBeforeEnd() public {
        _deposit();
        _bid(alice, 600e18, floorPrice + 50 * tickSpacing);
        vm.expectRevert(IRWALauncher.AuctionNotEnded.selector);
        launcher.build();
    }

    function test_fullLifecycle() public {
        _deposit();

        uint256 maxPrice = floorPrice + 50 * tickSpacing; // a valid tick above the floor
        uint256 aliceBid = _bid(alice, 600e18, maxPrice);
        _bid(bob, 600e18, maxPrice);

        // End the auction and build the position.
        vm.roll(startBlock + DURATION + 1);
        launcher.build();

        assertTrue(auction.isGraduated(), 'graduated');
        assertEq(uint256(launcher.stage()), uint256(Stage.ACTIVE), 'active');
        // Proceeds (currencyRaised, no protocol fee) routed to the issuer.
        assertEq(currency.balanceOf(issuer), 1_200e18, 'proceeds to issuer');
        // Pool seeded: launcher minted both legs and holds liquidity (pot is zero until unwind).
        assertGt(launcher.proceeds(), 0);

        // Winner claims shares.
        vm.roll(startBlock + DURATION + 2);
        auction.exitBid(aliceBid);
        auction.claimTokens(aliceBid);
        uint256 aliceShares = MockERC20(launcher.shareToken()).balanceOf(alice);
        assertGt(aliceShares, 0, 'alice has shares');

        // Unwind after the LP window.
        vm.roll(startBlock + DURATION + 50);
        launcher.unwind();
        assertEq(uint256(launcher.stage()), uint256(Stage.UNWOUND), 'unwound');
        assertGt(launcher.pot0(), 0, 'pot0');
        assertGt(launcher.pot1(), 0, 'pot1');

        // Redeem shares for the pro-rata underlying.
        vm.prank(alice);
        (uint256 a0, uint256 a1) = launcher.redeem(aliceShares, false);
        assertGt(a0, 0, 'redeemed token0');
        assertGt(a1, 0, 'redeemed token1');
        assertEq(MockERC20(launcher.shareToken()).balanceOf(alice), 0, 'shares burned');
    }
}
