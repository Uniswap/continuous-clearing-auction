// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IContinuousClearingAuction} from '../../src/interfaces/IContinuousClearingAuction.sol';
import {ConstantsLib} from '../../src/libraries/ConstantsLib.sol';
import {FixedPoint96} from '../../src/libraries/FixedPoint96.sol';
import {RWALauncherFactory} from '../../src/rwa/RWALauncherFactory.sol';
import {
    IRWALauncher, RWALauncherParameters, SideConfig, TrancheConfig
} from '../../src/rwa/interfaces/IRWALauncher.sol';
import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {IAllowanceTransfer} from 'permit2/src/interfaces/IAllowanceTransfer.sol';

/// @title DemoController
/// @notice Thin demo-only front end over {RWALauncherFactory}. Encapsulates the auction-parameter struct and
///         the Permit2 bidding dance so a simple UI can start auctions and place bids with scalar arguments.
/// @dev NOT for production. Uses fixed demo defaults (50/50 sides, 5/10/50/100bp tranches, 1bp tick axis).
contract DemoController {
    address internal constant PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;
    uint256 public constant Q96 = FixedPoint96.Q96;
    uint256 public constant TICK_SPACING = FixedPoint96.Q96 / 10_000; // 1bp granularity of the discount axis

    RWALauncherFactory public immutable FACTORY;
    address public immutable USDC;
    address public immutable POOL_MANAGER;
    int24 public immutable POOL_TICK_SPACING;
    uint24 public immutable POOL_FEE;

    uint256 internal _nonce;

    event AuctionStarted(
        address indexed issuer, address indexed launcher, address indexed auction, uint128 deposit, uint64 endBlock
    );
    event Bid(address indexed bidder, address indexed auction, uint128 amount, uint256 maxPriceQ96, uint256 bidId);

    constructor(
        RWALauncherFactory factory,
        address usdc,
        address poolManager,
        int24 poolTickSpacing,
        uint24 poolFee
    ) {
        FACTORY = factory;
        USDC = usdc;
        POOL_MANAGER = poolManager;
        POOL_TICK_SPACING = poolTickSpacing;
        POOL_FEE = poolFee;
        // Approve Permit2 to pull USDC from this controller for forwarding to auctions.
        IERC20(usdc).approve(PERMIT2, type(uint256).max);
    }

    /// @notice Start an auction. The issuer must first approve `deposit` USDC to this controller.
    /// @param deposit Issuer deposit / share supply (USDC base units)
    /// @param duration Auction length in blocks
    /// @param maxDiscountBps Worst discount the issuer will accept (sets the floor)
    /// @param requiredSharesSold Graduation threshold
    /// @param minter0 ITokenMinter for pool token0; minter1 for token1
    function startAuction(
        uint128 deposit,
        uint64 duration,
        uint16 maxDiscountBps,
        uint128 requiredSharesSold,
        address minter0,
        address token0,
        address minter1,
        address token1
    ) external returns (address launcher) {
        RWALauncherParameters memory p;
        p.currency = USDC;
        p.side0 = SideConfig({minter: minter0, token: token0, budgetWeightBps: 5_000});
        p.side1 = SideConfig({minter: minter1, token: token1, budgetWeightBps: 5_000});
        p.fundsRecipient = msg.sender;
        p.sharesRecipient = msg.sender;
        p.startBlock = uint64(block.number);
        p.endBlock = uint64(block.number) + duration;
        p.claimBlock = uint64(block.number) + duration + 1;
        p.lpDuration = 50;
        p.tickSpacing = TICK_SPACING;
        p.maxDiscountBps = maxDiscountBps;
        p.requiredSharesSold = requiredSharesSold;
        p.tranches = _defaultTranches();
        p.validationHook = address(0);
        p.auctionStepsData = abi.encodePacked(uint24(ConstantsLib.MPS / duration), uint40(duration));
        p.poolManager = POOL_MANAGER;
        p.poolTickSpacing = POOL_TICK_SPACING;
        p.poolFee = POOL_FEE;
        p.poolHooks = address(0);

        launcher = FACTORY.create(USDC, deposit, abi.encode(p), bytes32(_nonce++));

        IERC20(USDC).transferFrom(msg.sender, launcher, deposit);
        IRWALauncher(launcher).onTokensReceived();

        emit AuctionStarted(msg.sender, launcher, address(IRWALauncher(launcher).auction()), deposit, p.endBlock);
    }

    /// @notice Place a bid. The bidder must first approve `amount` USDC to this controller.
    /// @param auction The auction to bid in
    /// @param amount USDC committed
    /// @param maxPriceQ96 Max price per share (use {priceForDiscount})
    function bid(address auction, uint128 amount, uint256 maxPriceQ96) external returns (uint256 bidId) {
        IERC20(USDC).transferFrom(msg.sender, address(this), amount);
        IAllowanceTransfer(PERMIT2).approve(USDC, auction, uint160(amount), uint48(block.timestamp + 365 days));
        bidId = IContinuousClearingAuction(auction).submitBid(maxPriceQ96, amount, msg.sender, bytes(''));
        emit Bid(msg.sender, auction, amount, maxPriceQ96, bidId);
    }

    /// @notice The per-share max price for a given accepted discount, rounded to a tick boundary.
    function priceForDiscount(uint16 discountBps) external pure returns (uint256) {
        uint256 raw = (Q96 * (10_000 - discountBps)) / 10_000;
        return (raw / TICK_SPACING) * TICK_SPACING;
    }

    function _defaultTranches() internal pure returns (TrancheConfig[] memory t) {
        t = new TrancheConfig[](4);
        t[0] = TrancheConfig({rangeWidthBps: 5, weightBps: 1_000});
        t[1] = TrancheConfig({rangeWidthBps: 10, weightBps: 2_000});
        t[2] = TrancheConfig({rangeWidthBps: 50, weightBps: 3_000});
        t[3] = TrancheConfig({rangeWidthBps: 100, weightBps: 4_000});
    }
}
