// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ICheckpointStorage} from '../src/interfaces/ICheckpointStorage.sol';
import {Bid, BidLib} from '../src/libraries/BidLib.sol';
import {CheckpointAccountingLib} from '../src/libraries/CheckpointAccountingLib.sol';
import {Checkpoint} from '../src/libraries/CheckpointLib.sol';
import {CheckpointLib} from '../src/libraries/CheckpointLib.sol';
import {ConstantsLib} from '../src/libraries/ConstantsLib.sol';
import {FixedPoint96} from '../src/libraries/FixedPoint96.sol';
import {StepLib} from '../src/libraries/StepLib.sol';
import {ValueX7} from '../src/libraries/ValueX7Lib.sol';
import {Assertions} from './utils/Assertions.sol';
import {MockCheckpointStorage} from './utils/MockCheckpointStorage.sol';
import {Test} from 'forge-std/Test.sol';
import {FixedPointMathLib} from 'solady/utils/FixedPointMathLib.sol';

contract CheckpointStorageTest is Assertions, Test {
    MockCheckpointStorage public mockCheckpointStorage;

    using BidLib for Bid;
    using FixedPointMathLib for *;
    using StepLib for uint256;
    using ConstantsLib for *;

    uint256 public constant TICK_SPACING = 100;
    uint256 public constant ETH_AMOUNT = 10 ether * FixedPoint96.Q96;
    uint256 public constant FLOOR_PRICE = 100 << FixedPoint96.RESOLUTION;
    uint256 public constant MAX_PRICE = 500 << FixedPoint96.RESOLUTION;
    uint256 public constant TOKEN_AMOUNT = 100e18;
    uint256 public constant TOTAL_SUPPLY = 1000e18;

    function setUp() public {
        mockCheckpointStorage = new MockCheckpointStorage();
    }

    function test_insertCheckpoint_equalBlock_reverts() public {
        Checkpoint memory _checkpoint;
        mockCheckpointStorage.insertCheckpoint(_checkpoint, 100);
        vm.expectRevert(ICheckpointStorage.CheckpointBlockNotIncreasing.selector);
        mockCheckpointStorage.insertCheckpoint(_checkpoint, 100);
    }

    function test_insertCheckpoint_lowerBlock_reverts() public {
        Checkpoint memory _checkpoint;
        mockCheckpointStorage.insertCheckpoint(_checkpoint, 100);
        vm.expectRevert(ICheckpointStorage.CheckpointBlockNotIncreasing.selector);
        mockCheckpointStorage.insertCheckpoint(_checkpoint, 99);
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
        for (uint8 i = 1; i < n; i++) {
            Checkpoint memory _checkpoint;
            mockCheckpointStorage.insertCheckpoint(_checkpoint, i);
            _checkpoint = mockCheckpointStorage.getCheckpoint(i);
            assertEq(_checkpoint.prev, i - 1);
            assertEq(_checkpoint.next, type(uint64).max);
        }
    }

    function test_latestCheckpoint_returnsCheckpoint() public {
        // Initially, there should be no checkpoint (lastCheckpointedBlock = 0)
        Checkpoint memory checkpoint = mockCheckpointStorage.latestCheckpoint();

        // The checkpoint should be empty (all fields default to 0)
        assertEq(checkpoint.clearingPrice, 0);
        assertEq(checkpoint.cumulativeMps, 0);

        checkpoint.clearingPrice = 1;
        mockCheckpointStorage.insertCheckpoint(checkpoint, 1);
        Checkpoint memory _checkpoint = mockCheckpointStorage.getCheckpoint(1);
        assertEq(_checkpoint.clearingPrice, 1);
        assertEq(mockCheckpointStorage.latestCheckpoint(), _checkpoint);
    }

    function test_calculateFill_exactIn_fuzz_succeeds(
        uint128 _inputAmount,
        uint24 _startCumulativeMps,
        uint256 _cumulativeMpsPerPriceDelta,
        uint24 _cumulativeMpsDelta
    ) public view {
        vm.assume(_cumulativeMpsDelta <= ConstantsLib.MPS);
        vm.assume(_startCumulativeMps < ConstantsLib.MPS);
        // Add a reasonable bound for cumulativeMpsPerPriceDelta to avoid overflow
        _cumulativeMpsPerPriceDelta = _bound(_cumulativeMpsPerPriceDelta, 1, type(uint128).max);

        uint256 inputAmountQ96 = _inputAmount * FixedPoint96.Q96;
        // Assume that full mulDiv will not overflow
        vm.assume(inputAmountQ96 <= type(uint256).max / _cumulativeMpsPerPriceDelta);
        Bid memory bid = Bid({
            owner: address(this),
            amountQ96: inputAmountQ96,
            tokensFilled: 0,
            startBlock: 100,
            startCumulativeMps: _startCumulativeMps,
            exitedBlock: 0,
            maxPrice: MAX_PRICE // doesn't matter for this test
        });

        uint24 mpsRemainingInAuctionAfterSubmission = bid.mpsRemainingInAuctionAfterSubmission();

        (uint256 tokensFilled, uint256 currencySpentQ96) =
            CheckpointAccountingLib.calculateFill(bid, _cumulativeMpsPerPriceDelta, _cumulativeMpsDelta);

        assertEq(
            tokensFilled,
            inputAmountQ96.fullMulDiv(
                _cumulativeMpsPerPriceDelta,
                (FixedPoint96.Q96 << FixedPoint96.RESOLUTION) * mpsRemainingInAuctionAfterSubmission
            )
        );
        assertEq(
            currencySpentQ96, inputAmountQ96.fullMulDivUp(_cumulativeMpsDelta, mpsRemainingInAuctionAfterSubmission)
        );
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
            uint256 currencySpentInBlock = ETH_AMOUNT * mpsArray[i] / ConstantsLib.MPS;
            uint256 tokensFilledInBlock = uint256(currencySpentInBlock.fullMulDiv(FixedPoint96.Q96, pricesArray[i]));
            _tokensFilled += tokensFilledInBlock;
            _currencySpent += currencySpentInBlock;

            _totalMps += mpsArray[i];
            _cumulativeMpsPerPrice += CheckpointLib.getMpsPerPrice(mpsArray[i], pricesArray[i]);
        }

        Bid memory bid = Bid({
            owner: address(this),
            amountQ96: ETH_AMOUNT,
            tokensFilled: 0,
            startBlock: 100,
            startCumulativeMps: 0,
            exitedBlock: 0,
            maxPrice: MAX_PRICE // doesn't matter for this test
        });

        (uint256 tokensFilled, uint256 currencySpent) =
            CheckpointAccountingLib.calculateFill(bid, _cumulativeMpsPerPrice, uint24(_totalMps));

        assertEq(tokensFilled, _tokensFilled / FixedPoint96.Q96);
        assertEq(currencySpent, _currencySpent);
    }

    function test_calculateFill_exactIn_maxPrice() public view {
        uint24[] memory mpsArray = new uint24[](1);
        uint256[] memory pricesArray = new uint256[](1);

        mpsArray[0] = ConstantsLib.MPS;
        pricesArray[0] = MAX_PRICE;

        // Setup: Large ETH bid
        uint256 largeAmount = 100 ether * FixedPoint96.Q96;
        Bid memory bid = Bid({
            owner: address(this),
            amountQ96: largeAmount,
            tokensFilled: 0,
            startBlock: 100,
            startCumulativeMps: 0,
            exitedBlock: 0,
            maxPrice: MAX_PRICE // doesn't matter for this test
        });

        uint256 cumulativeMpsPerPriceDelta = CheckpointLib.getMpsPerPrice(mpsArray[0], pricesArray[0]);
        uint24 cumulativeMpsDelta = ConstantsLib.MPS;
        uint256 expectedCurrencySpent = largeAmount * cumulativeMpsDelta / ConstantsLib.MPS;

        uint256 expectedTokensFilled =
            uint256(expectedCurrencySpent.fullMulDiv(FixedPoint96.Q96, MAX_PRICE * FixedPoint96.Q96));

        (uint256 tokensFilled, uint256 currencySpent) =
            CheckpointAccountingLib.calculateFill(bid, cumulativeMpsPerPriceDelta, cumulativeMpsDelta);

        assertEq(tokensFilled, expectedTokensFilled);
        assertEq(currencySpent, expectedCurrencySpent);
    }

    function test_calculateFill_roundsSmallValuesToZero(
        uint256 _inputAmount,
        uint24 _startCumulativeMps,
        uint256 _cumulativeMpsPerPriceDelta,
        uint24 _cumulativeMpsDelta
    ) public view {
        vm.assume(_inputAmount > 0);
        vm.assume(_startCumulativeMps < ConstantsLib.MPS);
        _cumulativeMpsDelta = uint24(_bound(_cumulativeMpsDelta, 1, ConstantsLib.MPS));
        // prevent overflow
        _cumulativeMpsPerPriceDelta = _bound(_cumulativeMpsPerPriceDelta, 1, type(uint256).max / _inputAmount);
        // Assume that the bid amount when multiplied by the cumulative mps per price delta will be rounded to zero
        vm.assume(_inputAmount * _cumulativeMpsPerPriceDelta < FixedPoint96.Q96 * ConstantsLib.MPS);

        Bid memory bid;
        bid.amountQ96 = _inputAmount;
        bid.startCumulativeMps = _startCumulativeMps;

        (uint256 tokensFilled, uint256 currencySpent) =
            CheckpointAccountingLib.calculateFill(bid, _cumulativeMpsPerPriceDelta, _cumulativeMpsDelta);

        assertEq(tokensFilled, 0);
        // Currency spent is independent of the tokensFilled
        assertEq(
            currencySpent, _inputAmount.fullMulDivUp(_cumulativeMpsDelta, bid.mpsRemainingInAuctionAfterSubmission())
        );
    }

    function test_accountPartiallyFilledCheckpoints_zeroCumulativeSupplySoldToClearingPrice_returnsZero(Bid memory bid)
        public
        view
    {
        vm.assume(bid.startCumulativeMps < ConstantsLib.MPS);
        vm.assume(bid.mpsRemainingInAuctionAfterSubmission() > 0);
        vm.assume(bid.amountQ96 < type(uint128).max);
        vm.assume(bid.maxPrice > 0);

        Checkpoint memory _checkpoint = mockCheckpointStorage.latestCheckpoint();
        (uint256 tokensFilled, uint256 currencySpent) = mockCheckpointStorage.accountPartiallyFilledCheckpoints(
            bid, 1e18, _checkpoint.currencyRaisedAtClearingPriceQ96_X7
        );
        assertEq(tokensFilled, 0);
        assertEq(currencySpent, 0);
    }

    function test_accountPartiallyFilledCheckpoints_zeroTickDemand_returnsZero(Bid memory bid) public view {
        vm.assume(bid.startCumulativeMps < ConstantsLib.MPS);
        vm.assume(bid.mpsRemainingInAuctionAfterSubmission() > 0);
        vm.assume(bid.amountQ96 < type(uint128).max);
        vm.assume(bid.maxPrice > 0);

        Checkpoint memory _checkpoint = mockCheckpointStorage.latestCheckpoint();
        _checkpoint.currencyRaisedAtClearingPriceQ96_X7 = ValueX7.wrap(1e18);

        (uint256 tokensFilled, uint256 currencySpent) = mockCheckpointStorage.accountPartiallyFilledCheckpoints(
            bid,
            0, // tick demand
            _checkpoint.currencyRaisedAtClearingPriceQ96_X7
        );
        assertEq(tokensFilled, 0);
        assertEq(currencySpent, 0);
    }
}
