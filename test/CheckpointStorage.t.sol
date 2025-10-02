// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Tick} from '../src/TickStorage.sol';
import {AuctionStepLib} from '../src/libraries/AuctionStepLib.sol';
import {Bid, BidLib} from '../src/libraries/BidLib.sol';
import {Checkpoint} from '../src/libraries/CheckpointLib.sol';
import {CheckpointLib} from '../src/libraries/CheckpointLib.sol';
import {Demand, DemandLib} from '../src/libraries/DemandLib.sol';
import {FixedPoint96} from '../src/libraries/FixedPoint96.sol';
import {MPSLib} from '../src/libraries/MPSLib.sol';
import {ValueX7, ValueX7Lib} from '../src/libraries/ValueX7Lib.sol';
import {ValueX7X7, ValueX7X7Lib} from '../src/libraries/ValueX7X7Lib.sol';
import {Assertions} from './utils/Assertions.sol';
import {MockCheckpointStorage} from './utils/MockCheckpointStorage.sol';
import {Test} from 'forge-std/Test.sol';
import {FixedPointMathLib} from 'solady/utils/FixedPointMathLib.sol';

contract CheckpointStorageTest is Assertions, Test {
    MockCheckpointStorage public mockCheckpointStorage;

    using BidLib for Bid;
    using DemandLib for Demand;
    using FixedPointMathLib for uint256;
    using AuctionStepLib for uint256;
    using MPSLib for *;

    uint24 public constant MPS = 1e7;
    uint256 public constant TICK_SPACING = 100;
    uint256 public constant ETH_AMOUNT = 10 ether;
    uint256 public constant FLOOR_PRICE = 100 << FixedPoint96.RESOLUTION;
    uint256 public constant MAX_PRICE = 500 << FixedPoint96.RESOLUTION;
    uint256 public constant TOKEN_AMOUNT = 100e18;
    uint256 public constant TOTAL_SUPPLY = 1000e18;

    function setUp() public {
        mockCheckpointStorage = new MockCheckpointStorage();
    }

    function test_insertCheckpoint_firstCheckpoint_succeeds() public {
        Checkpoint memory _checkpoint;
        mockCheckpointStorage.insertCheckpoint(_checkpoint, 100);

        Checkpoint memory checkpoint = mockCheckpointStorage.getCheckpoint(100);
        assertEq(checkpoint.prev, 0);
        assertEq(checkpoint.next, type(uint64).max);
    }

    function test_insertCheckpoint_withPrev_succeeds() public {
        Checkpoint memory _checkpoint;
        mockCheckpointStorage.insertCheckpoint(_checkpoint, 100);
        mockCheckpointStorage.insertCheckpoint(_checkpoint, 101);

        Checkpoint memory prevCheckpoint = mockCheckpointStorage.getCheckpoint(100);
        assertEq(prevCheckpoint.prev, 0);
        assertEq(prevCheckpoint.next, 101);

        Checkpoint memory checkpoint = mockCheckpointStorage.getCheckpoint(101);
        assertEq(checkpoint.prev, 100);
        assertEq(checkpoint.next, type(uint64).max);
    }

    function test_insertCheckpoint_fuzz_succeeds(uint8 n) public {
        for (uint8 i = 0; i < n; i++) {
            Checkpoint memory _checkpoint;
            mockCheckpointStorage.insertCheckpoint(_checkpoint, i);
            _checkpoint = mockCheckpointStorage.getCheckpoint(i);
            if (i > 0) {
                assertEq(_checkpoint.prev, i - 1);
                assertEq(_checkpoint.next, type(uint64).max);
            } else {
                assertEq(_checkpoint.prev, 0);
                assertEq(_checkpoint.next, type(uint64).max);
            }
        }
    }

    function test_latestCheckpoint_returnsCheckpoint() public {
        // Initially, there should be no checkpoint (lastCheckpointedBlock = 0)
        Checkpoint memory checkpoint = mockCheckpointStorage.latestCheckpoint();

        // The checkpoint should be empty (all fields default to 0)
        assertEq(checkpoint.clearingPrice, 0);
        assertEq(checkpoint.totalClearedX7X7, ValueX7X7.wrap(0));
        assertEq(checkpoint.cumulativeMps, 0);

        checkpoint.clearingPrice = 1;
        mockCheckpointStorage.insertCheckpoint(checkpoint, 1);
        Checkpoint memory _checkpoint = mockCheckpointStorage.getCheckpoint(1);
        assertEq(_checkpoint.clearingPrice, 1);
        assertEq(mockCheckpointStorage.latestCheckpoint(), _checkpoint);
    }

    function test_calculateFill_exactIn_fuzz_succeeds(uint256 cumulativeMpsPerPriceDelta, uint24 cumulativeMpsDelta)
        public
        view
    {
        vm.assume(ETH_AMOUNT * (cumulativeMpsPerPriceDelta >> FixedPoint96.RESOLUTION) <= type(uint256).max);
        vm.assume(cumulativeMpsDelta <= MPS);
        // Setup: User commits 10 ETH to buy tokens
        Bid memory bid = Bid({
            exactIn: true,
            owner: address(this),
            amount: ETH_AMOUNT,
            tokensFilled: 0,
            startBlock: 100,
            startCumulativeMps: 0,
            exitedBlock: 0,
            maxPrice: MAX_PRICE // doesn't matter for this test
        });

        (uint256 tokensFilled, uint256 currencySpent) =
            mockCheckpointStorage.calculateFill(bid, cumulativeMpsPerPriceDelta, cumulativeMpsDelta);

        assertEq(tokensFilled, ETH_AMOUNT.fullMulDiv(cumulativeMpsPerPriceDelta, FixedPoint96.Q96 * MPS));
        if (tokensFilled != 0) {
            assertEq(currencySpent, ETH_AMOUNT * cumulativeMpsDelta / MPS);
        } else {
            assertEq(currencySpent, 0);
        }
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
            startCumulativeMps: 0,
            exitedBlock: 0,
            maxPrice: MAX_PRICE // doesn't matter for this test
        });

        uint256 maxPrice = 2000 << FixedPoint96.RESOLUTION;
        uint256 cumulativeMpsPerPrice = CheckpointLib.getMpsPerPrice(cumulativeMpsDelta, maxPrice);
        uint256 _tokensFilled = TOKEN_AMOUNT * cumulativeMpsDelta / MPS;
        uint256 _currencySpent =
            uint256(_tokensFilled.fullMulDivUp(cumulativeMpsDelta * FixedPoint96.Q96, cumulativeMpsPerPrice));

        (uint256 tokensFilled, uint256 currencySpent) =
            mockCheckpointStorage.calculateFill(bid, cumulativeMpsPerPrice, cumulativeMpsDelta);

        assertEq(tokensFilled, _tokensFilled);
        assertEq(currencySpent, _currencySpent);
    }

    function test_calculateFill_exactIn_iterative() public view {
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
        uint24 _totalMps;
        uint256 _cumulativeMpsPerPrice;

        for (uint256 i = 0; i < 3; i++) {
            uint256 currencySpentInBlock = ETH_AMOUNT * mpsArray[i] / MPS;
            uint256 tokensFilledInBlock = uint256(currencySpentInBlock.fullMulDiv(FixedPoint96.Q96, pricesArray[i]));
            _tokensFilled += tokensFilledInBlock;
            _currencySpent += currencySpentInBlock;

            _totalMps += mpsArray[i];
            _cumulativeMpsPerPrice += CheckpointLib.getMpsPerPrice(mpsArray[i], pricesArray[i]);
        }

        Bid memory bid = Bid({
            exactIn: true,
            owner: address(this),
            amount: ETH_AMOUNT,
            tokensFilled: 0,
            startBlock: 100,
            startCumulativeMps: 0,
            exitedBlock: 0,
            maxPrice: MAX_PRICE // doesn't matter for this test
        });

        (uint256 tokensFilled, uint256 currencySpent) =
            mockCheckpointStorage.calculateFill(bid, _cumulativeMpsPerPrice, uint24(_totalMps));

        assertEq(tokensFilled, _tokensFilled);
        assertEq(currencySpent, _currencySpent);
    }

    function test_calculateFill_exactOut() public view {
        uint24[] memory mpsArray = new uint24[](1);
        uint256[] memory pricesArray = new uint256[](1);

        mpsArray[0] = 1e7;
        pricesArray[0] = 100 << FixedPoint96.RESOLUTION;

        uint256 _totalMps;
        uint256 _cumulativeMpsPerPrice;
        uint256 _currencySpent;

        for (uint256 i = 0; i < 1; i++) {
            _totalMps += mpsArray[i];
            _cumulativeMpsPerPrice += CheckpointLib.getMpsPerPrice(mpsArray[i], pricesArray[i]);
            _currencySpent += uint256(TOKEN_AMOUNT.fullMulDiv(mpsArray[i] * FixedPoint96.Q96, _cumulativeMpsPerPrice));
        }

        Bid memory bid = Bid({
            exactIn: false,
            owner: address(this),
            amount: TOKEN_AMOUNT,
            tokensFilled: 0,
            startBlock: 100,
            startCumulativeMps: 0,
            exitedBlock: 0,
            maxPrice: MAX_PRICE // doesn't matter for this test
        });

        // Bid is fully filled since max price is always higher than all prices
        (uint256 tokensFilled, uint256 currencySpent) =
            mockCheckpointStorage.calculateFill(bid, _cumulativeMpsPerPrice, uint24(_totalMps));

        assertEq(_totalMps, 1e7);
        assertEq(tokensFilled, TOKEN_AMOUNT * 1e7 / MPS);
        assertEq(currencySpent, _currencySpent);
    }

    function test_calculateFill_exactIn_maxPrice() public view {
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
            startCumulativeMps: 0,
            exitedBlock: 0,
            maxPrice: MAX_PRICE // doesn't matter for this test
        });

        uint256 cumulativeMpsPerPriceDelta = CheckpointLib.getMpsPerPrice(mpsArray[0], pricesArray[0]);
        uint24 cumulativeMpsDelta = MPS;
        uint256 expectedCurrencySpent = largeAmount * cumulativeMpsDelta / MPS;

        uint256 expectedTokensFilled = uint256(expectedCurrencySpent.fullMulDiv(FixedPoint96.Q96, MAX_PRICE));

        (uint256 tokensFilled, uint256 currencySpent) =
            mockCheckpointStorage.calculateFill(bid, cumulativeMpsPerPriceDelta, cumulativeMpsDelta);

        assertEq(tokensFilled, expectedTokensFilled);
        assertEq(currencySpent, expectedCurrencySpent);
    }

    function test_accountPartiallyFilledCheckpoints_zeroCumulativeSupplySoldToClearingPrice_returnsZero() public view {
        Checkpoint memory _checkpoint = mockCheckpointStorage.latestCheckpoint();
        (uint256 tokensFilled, uint256 currencySpent) = mockCheckpointStorage.accountPartiallyFilledCheckpoints(
            _checkpoint.cumulativeSupplySoldToClearingPriceX7X7, ValueX7.wrap(1e18), ValueX7.wrap(1e18), 1e6
        );
        assertEq(tokensFilled, 0);
        assertEq(currencySpent, 0);
    }

    function test_accountPartiallyFilledCheckpoints_zeroTickDemand_returnsZero() public view {
        Checkpoint memory _checkpoint = mockCheckpointStorage.latestCheckpoint();
        _checkpoint.cumulativeSupplySoldToClearingPriceX7X7 = ValueX7X7.wrap(1e18);

        (uint256 tokensFilled, uint256 currencySpent) = mockCheckpointStorage.accountPartiallyFilledCheckpoints(
            _checkpoint.cumulativeSupplySoldToClearingPriceX7X7,
            ValueX7.wrap(0), // bid demand
            ValueX7.wrap(0), // tick demand
            1e6
        );
        assertEq(tokensFilled, 0);
        assertEq(currencySpent, 0);
    }
}
