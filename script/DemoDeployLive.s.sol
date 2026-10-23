// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ContinuousClearingAuctionFactory} from '../src/ContinuousClearingAuctionFactory.sol';
import {ConstantsLib} from '../src/libraries/ConstantsLib.sol';
import {FixedPoint96} from '../src/libraries/FixedPoint96.sol';
import {RWALauncher} from '../src/rwa/RWALauncher.sol';
import {RWALauncherFactory} from '../src/rwa/RWALauncherFactory.sol';
import {
    RWALauncherParameters, SideConfig, TrancheConfig
} from '../src/rwa/interfaces/IRWALauncher.sol';
import {DemoController} from '../demo/contracts/DemoController.sol';
import {DemoERC20} from '../demo/contracts/DemoERC20.sol';
import {MockTokenMinter} from '../test/rwa/mocks/MockTokenMinter.sol';
import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {Script} from 'forge-std/Script.sol';
import {PoolManager} from 'v4-periphery/lib/v4-core/src/PoolManager.sol';

/// @notice Deploys the demo stack and starts ONE shared auction so anyone can bid. Works on any chain that
///         enforces EIP-170 (e.g. Sepolia): the launcher is deployed directly rather than via the oversized
///         RWALauncherFactory. Run:
///   PRIVATE_KEY=0x.. forge script script/DemoDeployLive.s.sol --rpc-url $SEPOLIA_RPC --broadcast
contract DemoDeployLive is Script {
    uint256 internal constant Q96 = FixedPoint96.Q96;
    uint256 internal constant ONE = 1e18;

    function run() external {
        uint256 pk = vm.envUint('PRIVATE_KEY');
        address deployer = vm.addr(pk);
        uint256 startBlock = block.number;
        uint128 deposit = uint128(vm.envOr('DEPOSIT', uint256(2_000)) * ONE);
        uint64 duration = uint64(vm.envOr('DURATION', uint256(600))); // blocks (~2h on Sepolia)
        uint16 maxDiscountBps = uint16(vm.envOr('MAX_DISCOUNT_BPS', uint256(100)));
        uint128 required = uint128(vm.envOr('REQUIRED', uint256(1_000)) * ONE);

        vm.startBroadcast(pk);

        DemoERC20 usdc = new DemoERC20('Demo USD Coin', 'dUSDC', 18, 1_000_000 * ONE);
        DemoERC20 qqq = new DemoERC20('Demo QQQ', 'dQQQ', 18, 0);
        DemoERC20 ant = new DemoERC20('Demo Anthropic', 'dANT', 18, 0);
        MockTokenMinter minterQ = new MockTokenMinter(address(usdc), address(qqq), 500 * Q96);
        MockTokenMinter minterA = new MockTokenMinter(address(usdc), address(ant), 150 * Q96);
        qqq.setMinter(address(minterQ), true);
        ant.setMinter(address(minterA), true);

        PoolManager poolManager = new PoolManager(deployer);
        ContinuousClearingAuctionFactory ccaFactory = new ContinuousClearingAuctionFactory(address(0));
        // factory unused on-chain here (auction is pre-created); the controller only needs USDC for bidding.
        DemoController controller =
            new DemoController(RWALauncherFactory(address(0)), address(usdc), address(poolManager), int24(60), uint24(3_000));

        // Deploy the launcher directly (the factory is over EIP-170), then start the auction.
        RWALauncher launcher = new RWALauncher(deposit, _params(usdc, qqq, ant, minterQ, minterA, poolManager, deployer, duration, maxDiscountBps, required), ccaFactory);
        address auction = address(launcher.auction());

        usdc.faucet(); // deployer gets test dUSDC
        IERC20(address(usdc)).transfer(address(launcher), deposit);
        launcher.onTokensReceived();

        vm.stopBroadcast();

        string memory o = 'demo';
        vm.serializeUint(o, 'chainId', block.chainid);
        vm.serializeAddress(o, 'usdc', address(usdc));
        vm.serializeAddress(o, 'qqq', address(qqq));
        vm.serializeAddress(o, 'ant', address(ant));
        vm.serializeAddress(o, 'minterQ', address(minterQ));
        vm.serializeAddress(o, 'minterA', address(minterA));
        vm.serializeAddress(o, 'poolManager', address(poolManager));
        vm.serializeAddress(o, 'ccaFactory', address(ccaFactory));
        vm.serializeAddress(o, 'controller', address(controller));
        vm.serializeAddress(o, 'launcher', address(launcher));
        vm.serializeAddress(o, 'auction', auction);
        vm.serializeUint(o, 'startBlock', startBlock);
        vm.serializeUint(o, 'endBlock', startBlock + duration);
        vm.serializeAddress(o, 'permit2', 0x000000000022D473030F116dDEE9F6B43aC78BA3);
        vm.serializeUint(o, 'maxDiscountBps', uint256(maxDiscountBps));
        vm.serializeUint(o, 'qqqPriceUsd', 500);
        vm.serializeUint(o, 'antPriceUsd', 150);
        string memory out = vm.serializeAddress(o, 'issuer', deployer);
        vm.writeJson(out, 'demo/web/addresses.json');
    }

    function _params(
        DemoERC20 usdc,
        DemoERC20 qqq,
        DemoERC20 ant,
        MockTokenMinter minterQ,
        MockTokenMinter minterA,
        PoolManager poolManager,
        address issuer,
        uint64 duration,
        uint16 maxDiscountBps,
        uint128 required
    ) internal view returns (RWALauncherParameters memory p) {
        p.currency = address(usdc);
        p.side0 = SideConfig({minter: address(minterQ), token: address(qqq), budgetWeightBps: 5_000});
        p.side1 = SideConfig({minter: address(minterA), token: address(ant), budgetWeightBps: 5_000});
        p.fundsRecipient = issuer;
        p.sharesRecipient = issuer;
        p.startBlock = uint64(block.number);
        p.endBlock = uint64(block.number) + duration;
        p.claimBlock = uint64(block.number) + duration + 1;
        p.lpDuration = 300;
        p.tickSpacing = Q96 / 10_000;
        p.maxDiscountBps = maxDiscountBps;
        p.requiredSharesSold = required;
        p.tranches = new TrancheConfig[](4);
        p.tranches[0] = TrancheConfig({rangeWidthBps: 5, weightBps: 1_000});
        p.tranches[1] = TrancheConfig({rangeWidthBps: 10, weightBps: 2_000});
        p.tranches[2] = TrancheConfig({rangeWidthBps: 50, weightBps: 3_000});
        p.tranches[3] = TrancheConfig({rangeWidthBps: 100, weightBps: 4_000});
        p.validationHook = address(0);
        p.auctionStepsData = _steps(duration);
        p.poolManager = address(poolManager);
        p.poolTickSpacing = int24(60);
        p.poolFee = uint24(3_000);
        p.poolHooks = address(0);
    }

    /// @dev A two-step issuance schedule whose cumulative mps lands exactly on MPS (required) for any
    ///      duration >= 2: a flat base rate over `duration-1` blocks, then a final block absorbing the remainder.
    function _steps(uint64 duration) internal pure returns (bytes memory) {
        uint24 base = uint24(ConstantsLib.MPS / duration);
        uint24 last = uint24(ConstantsLib.MPS - uint256(base) * (duration - 1));
        return abi.encodePacked(base, uint40(duration - 1), last, uint40(1));
    }
}
