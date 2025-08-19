// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Tick} from '../src/TickStorage.sol';
import {AuctionStepLib} from '../src/libraries/AuctionStepLib.sol';

import {Bid, BidLib} from '../src/libraries/BidLib.sol';
import {Demand, DemandLib} from '../src/libraries/DemandLib.sol';
import {FixedPoint96} from '../src/libraries/FixedPoint96.sol';
import {MockCheckpointStorage} from './utils/MockCheckpointStorage.sol';
import {Test} from 'forge-std/Test.sol';

import {console2} from 'forge-std/console2.sol';
import {FixedPointMathLib} from 'solady/utils/FixedPointMathLib.sol';

contract CheckpointStorageTest is Test {
    MockCheckpointStorage mockCheckpointStorage;

    using BidLib for Bid;
    using DemandLib for Demand;
    using FixedPointMathLib for uint256;
    using AuctionStepLib for uint256;

    uint24 public constant MPS = 1e7;
    uint256 public constant TICK_SPACING = 100;
    uint256 public constant ETH_AMOUNT = 10 ether;
    uint256 public constant FLOOR_PRICE = 100 << FixedPoint96.RESOLUTION;
    uint256 public constant MAX_PRICE = 500 << FixedPoint96.RESOLUTION;
    uint256 public constant TOKEN_AMOUNT = 100e18;
    uint256 public constant TOTAL_SUPPLY = 1000e18;

    function setUp() public {
        mockCheckpointStorage = new MockCheckpointStorage(FLOOR_PRICE, TICK_SPACING);
    }

    function test_resolve_exactOut_calculatePartialFill_succeeds() public view {
        // Buy exactly 100 tokens at max price 2000 per token
        uint256 exactOutAmount = 1000e18;
        uint256 maxPrice = 2000 << FixedPoint96.RESOLUTION;
        Bid memory bid = Bid({
            exactIn: false,
            owner: address(this),
            amount: exactOutAmount,
            tokensFilled: 0,
            startBlock: 100,
            exitedBlock: 0,
            maxPrice: maxPrice
        });
        Tick memory tick = Tick({next: 0, demand: Demand({currencyDemand: 0, tokenDemand: exactOutAmount})});

        // Execute: 30% of auction executed (3000 mps)
        uint24 cumulativeMpsDelta = 3000e3;

        // Calculate partial fill values
        uint256 bidDemand = bid.demand();
        assertEq(bidDemand, exactOutAmount);
        uint256 tickDemand = tick.demand.resolve(maxPrice);
        // No one else at tick, so demand is the same
        assertEq(bidDemand, tickDemand);
        uint256 supply = TOTAL_SUPPLY.applyMps(cumulativeMpsDelta);

        // First case, no other demand, bid is "fully filled"
        uint256 resolvedDemandAboveClearingPrice = 0;
        uint256 tokensFilled;
        uint256 currencySpent;
        (tokensFilled, currencySpent) = mockCheckpointStorage.calculatePartialFill(
            bidDemand, tickDemand, maxPrice, supply, cumulativeMpsDelta, resolvedDemandAboveClearingPrice
        );

        // 30% of 1000e18 tokens = 300e18 tokens filled
        assertEq(tokensFilled, 300e18);
        // All tokens were purchased at the bid's max price
        assertEq(currencySpent, tokensFilled * maxPrice);
    }

    function test_resolve_exactIn_fuzz_succeeds(uint256 cumulativeMpsPerPriceDelta, uint24 cumulativeMpsDelta)
        public
        view
    {
        vm.assume(cumulativeMpsDelta <= MPS);
        // Setup: User commits 10 ETH to buy tokens
        Bid memory bid = Bid({
            exactIn: true,
            owner: address(this),
            amount: ETH_AMOUNT,
            tokensFilled: 0,
            startBlock: 100,
            exitedBlock: 0,
            maxPrice: MAX_PRICE // doesn't matter for this test
        });

        (uint256 tokensFilled, uint256 currencySpent) =
            mockCheckpointStorage.calculateFill(bid, cumulativeMpsPerPriceDelta, cumulativeMpsDelta, MPS);

        assertEq(tokensFilled, ETH_AMOUNT.fullMulDiv(cumulativeMpsPerPriceDelta, FixedPoint96.Q96 * MPS));
        assertEq(currencySpent, ETH_AMOUNT.applyMps(cumulativeMpsDelta));
    }

    function test_resolve_exactOut_fuzz_succeeds(uint24 cumulativeMpsDelta) public view {
        vm.assume(cumulativeMpsDelta <= MPS && cumulativeMpsDelta > 0);
        // Setup: User commits to buy 100 tokens at max price 2000 per token
        Bid memory bid = Bid({
            exactIn: false,
            owner: address(this),
            amount: TOKEN_AMOUNT,
            tokensFilled: 0,
            startBlock: 100,
            exitedBlock: 0,
            maxPrice: MAX_PRICE // doesn't matter for this test
        });

        uint256 maxPrice = 2000 << FixedPoint96.RESOLUTION;
        uint256 cumulativeMpsPerPrice = (uint256(cumulativeMpsDelta) << FixedPoint96.RESOLUTION) / maxPrice;
        uint256 _tokensFilled = TOKEN_AMOUNT.applyMps(cumulativeMpsDelta);
        console2.log('tokensFilled', _tokensFilled);
        console2.log('cumulativeMpsDelta', cumulativeMpsDelta);
        console2.log('cumulativeMpsPerPrice', cumulativeMpsPerPrice);
        uint256 _currencySpent = _tokensFilled.fullMulDiv(cumulativeMpsDelta, cumulativeMpsPerPrice);

        (uint256 tokensFilled, uint256 currencySpent) =
            mockCheckpointStorage.calculateFill(bid, cumulativeMpsPerPrice, cumulativeMpsDelta, MPS);

        assertEq(tokensFilled, _tokensFilled);
        assertEq(currencySpent, _currencySpent);
    }

    function test_resolve_exactIn_iterative() public view {
        uint24[] memory mpsArray = new uint24[](3);
        uint256[] memory pricesArray = new uint256[](3);

        mpsArray[0] = 50e3;
        pricesArray[0] = 100 << FixedPoint96.RESOLUTION;

        mpsArray[1] = 30e3;
        pricesArray[1] = 200 << FixedPoint96.RESOLUTION;

        mpsArray[2] = 20e3;
        pricesArray[2] = 200 << FixedPoint96.RESOLUTION;

        uint256 _tokensFilled;
        uint256 _currencySpent;
        uint256 _totalMps;
        uint256 _cumulativeMpsPerPrice;

        for (uint256 i = 0; i < 3; i++) {
            uint256 currencySpentInBlock = ETH_AMOUNT * mpsArray[i] / MPS;
            uint256 tokensFilledInBlock = currencySpentInBlock.fullMulDiv(FixedPoint96.Q96, pricesArray[i]);
            _tokensFilled += tokensFilledInBlock;
            _currencySpent += currencySpentInBlock;

            _totalMps += mpsArray[i];
            _cumulativeMpsPerPrice += (uint256(mpsArray[i]) << (FixedPoint96.RESOLUTION * 2)) / pricesArray[i];
        }

        Bid memory bid = Bid({
            exactIn: true,
            owner: address(this),
            amount: ETH_AMOUNT,
            tokensFilled: 0,
            startBlock: 100,
            exitedBlock: 0,
            maxPrice: MAX_PRICE // doesn't matter for this test
        });

        (uint256 tokensFilled, uint256 currencySpent) =
            mockCheckpointStorage.calculateFill(bid, _cumulativeMpsPerPrice, uint24(_totalMps), MPS);

        assertEq(tokensFilled, _tokensFilled);
        assertEq(currencySpent, _currencySpent);
    }

    function test_resolve_exactOut() public view {
        uint256[] memory mpsArray = new uint256[](1);
        uint256[] memory pricesArray = new uint256[](1);

        mpsArray[0] = 1e7;
        pricesArray[0] = 100 << FixedPoint96.RESOLUTION;

        uint256 _totalMps;
        uint256 _cumulativeMpsPerPrice;
        uint256 _currencySpent;

        for (uint256 i = 0; i < 1; i++) {
            _totalMps += mpsArray[i];
            _cumulativeMpsPerPrice += (uint256(mpsArray[i]) << FixedPoint96.RESOLUTION) / pricesArray[i];
            _currencySpent += TOKEN_AMOUNT.fullMulDiv(mpsArray[i], _cumulativeMpsPerPrice);
        }

        Bid memory bid = Bid({
            exactIn: false,
            owner: address(this),
            amount: TOKEN_AMOUNT,
            tokensFilled: 0,
            startBlock: 100,
            exitedBlock: 0,
            maxPrice: MAX_PRICE // doesn't matter for this test
        });

        // Bid is fully filled since max price is always higher than all prices
        (uint256 tokensFilled, uint256 currencySpent) =
            mockCheckpointStorage.calculateFill(bid, _cumulativeMpsPerPrice, uint24(_totalMps), MPS);

        assertEq(_totalMps, 1e7);
        assertEq(tokensFilled, TOKEN_AMOUNT.applyMps(1e7));
        assertEq(currencySpent, _currencySpent);
    }

    function test_resolve_exactIn_maxPrice() public view {
        uint24[] memory mpsArray = new uint24[](1);
        uint256[] memory pricesArray = new uint256[](1);

        mpsArray[0] = MPS;
        pricesArray[0] = MAX_PRICE;

        // Setup: Large ETH bid
        uint256 largeAmount = 100 ether;
        Bid memory bid = Bid({
            exactIn: true,
            owner: address(this),
            amount: largeAmount,
            tokensFilled: 0,
            startBlock: 100,
            exitedBlock: 0,
            maxPrice: MAX_PRICE // doesn't matter for this test
        });

        // uint24.max << 96 will not overflow
        uint256 cumulativeMpsPerPriceDelta = (uint256(mpsArray[0]) << (FixedPoint96.RESOLUTION * 2)) / pricesArray[0];
        uint24 cumulativeMpsDelta = MPS;
        uint256 expectedCurrencySpent = largeAmount * cumulativeMpsDelta / MPS;

        uint256 expectedTokensFilled = expectedCurrencySpent.fullMulDiv(FixedPoint96.Q96, MAX_PRICE);

        (uint256 tokensFilled, uint256 currencySpent) =
            mockCheckpointStorage.calculateFill(bid, cumulativeMpsPerPriceDelta, cumulativeMpsDelta, MPS);

        assertEq(tokensFilled, expectedTokensFilled);
        assertEq(currencySpent, expectedCurrencySpent);
    }
}
