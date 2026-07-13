// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ConstantsLib} from '../src/libraries/ConstantsLib.sol';
import {FixedPoint96} from '../src/libraries/FixedPoint96.sol';
import {RWALauncher} from '../src/rwa/RWALauncher.sol';
import {RWALauncherFactory} from '../src/rwa/RWALauncherFactory.sol';
import {ContinuousClearingAuctionFactory} from '../src/ContinuousClearingAuctionFactory.sol';
import {RWALauncherParameters, SideConfig, TrancheConfig} from '../src/rwa/interfaces/IRWALauncher.sol';
import {DemoERC20} from '../demo/contracts/DemoERC20.sol';
import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {Script} from 'forge-std/Script.sol';

/// @notice Starts a fresh, SHORT auction reusing infra already deployed by DemoDeployLive (read from
///         demo/web/addresses.json), so the demo can be settled within a couple of minutes without
///         redeploying PoolManager/tokens. Each run uses a distinct pool fee so it stays repeatable.
///   PRIVATE_KEY=0x.. DURATION=10 forge script script/DemoNewAuction.s.sol --rpc-url $SEPOLIA_RPC --broadcast
contract DemoNewAuction is Script {
    uint256 internal constant Q96 = FixedPoint96.Q96;
    uint256 internal constant ONE = 1e18;

    function run() external {
        string memory j = vm.readFile('demo/web/addresses.json');
        address usdc = vm.parseJsonAddress(j, '.usdc');
        address qqq = vm.parseJsonAddress(j, '.qqq');
        address ant = vm.parseJsonAddress(j, '.ant');
        address minterQ = vm.parseJsonAddress(j, '.minterQ');
        address minterA = vm.parseJsonAddress(j, '.minterA');
        address poolManager = vm.parseJsonAddress(j, '.poolManager');
        address ccaFactory = vm.parseJsonAddress(j, '.ccaFactory');

        uint256 pk = vm.envUint('PRIVATE_KEY');
        address deployer = vm.addr(pk);
        uint256 startBlock = block.number;
        uint128 deposit = uint128(vm.envOr('DEPOSIT', uint256(2_000)) * ONE);
        uint64 duration = uint64(vm.envOr('DURATION', uint256(10))); // ~2 min on Sepolia
        uint16 maxDiscountBps = uint16(vm.envOr('MAX_DISCOUNT_BPS', uint256(100)));
        uint128 required = uint128(vm.envOr('REQUIRED', uint256(1_000)) * ONE);
        // Distinct pool fee per run keeps the v4 pool key unique, so repeated demos can each build.
        uint24 poolFee = uint24(3_000 + (startBlock % 50_000));

        RWALauncherParameters memory p;
        p.currency = usdc;
        p.side0 = SideConfig({minter: minterQ, token: qqq, budgetWeightBps: 5_000});
        p.side1 = SideConfig({minter: minterA, token: ant, budgetWeightBps: 5_000});
        p.fundsRecipient = deployer;
        p.sharesRecipient = deployer;
        p.startBlock = uint64(startBlock);
        p.endBlock = uint64(startBlock) + duration;
        p.claimBlock = uint64(startBlock) + duration + 1;
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
        {
            uint24 base = uint24(ConstantsLib.MPS / duration);
            uint24 last = uint24(ConstantsLib.MPS - uint256(base) * (duration - 1));
            p.auctionStepsData = abi.encodePacked(base, uint40(duration - 1), last, uint40(1));
        }
        p.poolManager = poolManager;
        p.poolTickSpacing = int24(60);
        p.poolFee = poolFee;
        p.poolHooks = address(0);

        vm.startBroadcast(pk);
        DemoERC20(usdc).faucet();
        RWALauncher launcher = new RWALauncher(deposit, p, ContinuousClearingAuctionFactory(ccaFactory));
        IERC20(usdc).transfer(address(launcher), deposit);
        launcher.onTokensReceived();
        vm.stopBroadcast();

        // Rewrite addresses.json, preserving infra fields and updating the auction.
        string memory o = 'demo';
        vm.serializeUint(o, 'chainId', vm.parseJsonUint(j, '.chainId'));
        vm.serializeAddress(o, 'usdc', usdc);
        vm.serializeAddress(o, 'qqq', qqq);
        vm.serializeAddress(o, 'ant', ant);
        vm.serializeAddress(o, 'minterQ', minterQ);
        vm.serializeAddress(o, 'minterA', minterA);
        vm.serializeAddress(o, 'poolManager', poolManager);
        vm.serializeAddress(o, 'ccaFactory', ccaFactory);
        vm.serializeAddress(o, 'controller', vm.parseJsonAddress(j, '.controller'));
        vm.serializeAddress(o, 'launcher', address(launcher));
        vm.serializeAddress(o, 'auction', address(launcher.auction()));
        vm.serializeUint(o, 'startBlock', startBlock);
        vm.serializeUint(o, 'endBlock', startBlock + duration);
        vm.serializeAddress(o, 'permit2', 0x000000000022D473030F116dDEE9F6B43aC78BA3);
        vm.serializeUint(o, 'maxDiscountBps', uint256(maxDiscountBps));
        vm.serializeUint(o, 'qqqPriceUsd', vm.parseJsonUint(j, '.qqqPriceUsd'));
        vm.serializeUint(o, 'antPriceUsd', vm.parseJsonUint(j, '.antPriceUsd'));
        string memory out = vm.serializeAddress(o, 'issuer', deployer);
        vm.writeJson(out, 'demo/web/addresses.json');
    }
}
