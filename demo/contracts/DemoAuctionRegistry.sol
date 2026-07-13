// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {DemoLaunchpad} from './DemoLaunchpad.sol';
import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';

/// @title DemoAuctionRegistry
/// @notice DEMO-ONLY registry + factory. `createAndRegister()` deploys a fresh {DemoLaunchpad} (reusing the
///         shared test tokens/minters/PoolManager), funds its deposit from the caller, opens bidding, and
///         appends it to the registry. Every client reads `latest()` so everyone converges on the same
///         current auction. Permissionless: anyone can reset the demo. Not for production.
/// @custom:security-contact security@uniswap.org
contract DemoAuctionRegistry {
    address public immutable USDC;
    address public immutable QQQ;
    address public immutable ANT;
    address public immutable MINTER_Q;
    address public immutable MINTER_A;
    address public immutable POOL_MANAGER;
    int24 public immutable POOL_TICK_SPACING;
    uint128 public immutable DEPOSIT;
    uint16 public immutable MAX_DISCOUNT_BPS;

    address[] public auctions;
    uint256 internal _nonce;

    event AuctionCreated(address indexed auction, address indexed creator, uint256 indexed index, bytes32 poolId);

    constructor(
        address usdc,
        address qqq,
        address ant,
        address minterQ,
        address minterA,
        address poolManager,
        int24 poolTickSpacing,
        uint128 deposit,
        uint16 maxDiscountBps
    ) {
        USDC = usdc;
        QQQ = qqq;
        ANT = ant;
        MINTER_Q = minterQ;
        MINTER_A = minterA;
        POOL_MANAGER = poolManager;
        POOL_TICK_SPACING = poolTickSpacing;
        DEPOSIT = deposit;
        MAX_DISCOUNT_BPS = maxDiscountBps;
    }

    /// @notice Deploy + fund + open a fresh auction and register it as the latest. The caller (the new
    ///         auction's issuer) must first approve `DEPOSIT` of USDC to this registry.
    function createAndRegister() external returns (address auction) {
        // Distinct pool fee per auction keeps each v4 pool key unique so every round can build its own pool.
        uint24 poolFee = uint24(3_000 + (_nonce++ % 40_000) + (block.number % 1_000));

        DemoLaunchpad pad = new DemoLaunchpad(
            msg.sender, USDC, DEPOSIT, MAX_DISCOUNT_BPS, MINTER_Q, QQQ, MINTER_A, ANT, POOL_MANAGER, POOL_TICK_SPACING, poolFee
        );
        IERC20(USDC).transferFrom(msg.sender, address(pad), DEPOSIT);
        pad.start();

        auction = address(pad);
        auctions.push(auction);
        emit AuctionCreated(auction, msg.sender, auctions.length - 1, pad.poolId());
    }

    /// @notice The current auction (address(0) if none yet).
    function latest() external view returns (address) {
        uint256 n = auctions.length;
        return n == 0 ? address(0) : auctions[n - 1];
    }

    function count() external view returns (uint256) {
        return auctions.length;
    }
}
