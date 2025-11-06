// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Checkpoint} from '../src/CheckpointStorage.sol';
import {AuctionParameters} from '../src/ContinuousClearingAuction.sol';
import {Bid} from '../src/libraries/BidLib.sol';
import {FixedPoint96} from '../src/libraries/FixedPoint96.sol';
import {AuctionStep} from '../src/libraries/StepLib.sol';
import {ValueX7, ValueX7Lib} from '../src/libraries/ValueX7Lib.sol';
import {AuctionBaseTest} from './utils/AuctionBaseTest.sol';
import {AuctionParamsBuilder} from './utils/AuctionParamsBuilder.sol';
import {AuctionStepsBuilder} from './utils/AuctionStepsBuilder.sol';
import {MockContinuousClearingAuction} from './utils/MockAuction.sol';

contract Leftovers is AuctionBaseTest {
    using AuctionParamsBuilder for AuctionParameters;
    using AuctionStepsBuilder for bytes;
    using ValueX7Lib for *;

    // bob is already set in AuctionBaseTest
    address private charlie;

    // Storage variables to avoid stack too deep
    uint256 private tick10;
    uint256 private tick20;
    uint256 private tick30;
    MockContinuousClearingAuction private mockAuction;

    uint256 private bidId1;
    uint256 private bidId2;

    bool internal expectReverts = false;

    function setUp() public {
        setUpAuction();
        bob = makeAddr('bob');
        charlie = makeAddr('charlie');
    }

    function test_largeTickSpacing_causesBurnAuction_earlySweep() public {
        _test_largeTickSpacing_causesBurnAuction(true, true);
    }

    function test_largeTickSpacing_causesBurnAuction_lateSweep() public {
        _test_largeTickSpacing_causesBurnAuction(true, false);
    }

    function _test_largeTickSpacing_causesBurnAuction(bool _withSecondBid, bool _sweepEarly) public {
        _setupLargeTickAuction();

        AuctionStep memory step = mockAuction.step();

        emit log_named_uint('Bid1 block', block.number);

        uint128 currency1 = inputAmountForTokens(TOTAL_SUPPLY, tick20);
        emit log_named_decimal_uint('Currency1 calculated', currency1, 18);
        bidId1 = mockAuction.submitBid{value: currency1}(tick20, currency1, bob, tick10, bytes(''));
        {
            Bid memory bid1 = mockAuction.getBid(bidId1);
            emit log_named_decimal_uint('B1, maxPrice', bid1.maxPrice / 1e14, 18);
        }

        vm.roll(block.number + 1);
        Checkpoint memory cp1 = mockAuction.checkpoint();
        emit log_named_uint('Cp1, block', block.number);
        emit log_named_decimal_uint('Cp1, Price after bid1', cp1.clearingPrice / 1e14, 18);
        emit log_named_decimal_uint('Cp1, raised', ValueX7.unwrap(mockAuction.currencyRaisedQ96_X7()) / 1e14, 18);

        // PERIOD 2: Add second bid at tick30
        if (_withSecondBid) {
            vm.roll(block.number + 1);
            emit log_named_uint('Bid2 block', block.number);
            uint128 currency2 = inputAmountForTokens(710e18, tick30);
            emit log_named_decimal_uint('Currency2 calculated', currency2, 18);
            bidId2 = mockAuction.submitBid{value: currency2}(tick30, currency2, alice, tick20, bytes(''));
            {
                Bid memory bid2 = mockAuction.getBid(bidId2);
                emit log_named_decimal_uint('B2, maxPrice', bid2.maxPrice / 1e14, 18);
            }

            vm.roll(block.number + 1);
            emit log_named_uint('Cp2, block', block.number);
            Checkpoint memory cp2 = mockAuction.checkpoint();
            emit log_named_decimal_uint('Cp2, raised', ValueX7.unwrap(mockAuction.currencyRaisedQ96_X7()) / 1e7, 18);
            emit log_named_decimal_uint('Cp2, Price after second bid', cp2.clearingPrice / 1e14, 18);
            emit log_named_decimal_uint('Cp2, Cumulative MPS', cp2.cumulativeMps, 5);
        }

        {
            vm.roll(block.number + 1);
            Checkpoint memory cp3 = mockAuction.checkpoint();
            emit log_named_decimal_uint('Cp3, raised', ValueX7.unwrap(mockAuction.currencyRaisedQ96_X7()) / 1e7, 18);
            emit log_named_decimal_uint('Cp3, Price after second bid', cp3.clearingPrice / 1e14, 18);
            emit log_named_decimal_uint('Cp3, Cumulative MPS', cp3.cumulativeMps, 5);
        }

        // Roll to end
        vm.roll(step.endBlock);
        Checkpoint memory finalCheckpoint = mockAuction.checkpoint();

        emit log_named_uint('Final checkpoint block', block.number);

        bool graduated = mockAuction.isGraduated();
        uint256 raised = ValueX7.unwrap(mockAuction.currencyRaisedQ96_X7()) / 1e7;

        emit log('==================== FINAL CHECKPOINT ====================');
        emit log_named_decimal_uint('Raised', raised, 18);
        emit log_named_decimal_uint('Balance of auction', address(mockAuction).balance, 18);
        emit log_named_decimal_uint('Price', finalCheckpoint.clearingPrice / 1e14, 18);
        emit log_named_decimal_uint('P-10 ', tick10 / 1e14, 18);
        emit log_named_decimal_uint('P-20 ', tick20 / 1e14, 18);
        emit log_named_decimal_uint('P-30 ', tick30 / 1e14, 18);
        emit log_named_decimal_uint('Cumulative MPS', finalCheckpoint.cumulativeMps, 5);
        emit log_named_string('Graduated', graduated ? 'true' : 'false');
        emit log_named_decimal_uint('Currency raised', mockAuction.currencyRaised(), 18);

        if (!_sweepEarly) {
            exitAndClaim(_sweepEarly);
        }

        _sweep(_sweepEarly);

        if (_sweepEarly) {
            exitAndClaim(_sweepEarly);
        }

        _finalBalances('==================== FINAL BALANCES ====================');
    }

    function exitAndClaim(bool _sweepEarly) public {
        mockAuction.checkpoint();
        uint256 raised = mockAuction.currencyRaised();

        {
            emit log('==================== EXITING BIDS ====================');
            Bid memory bid1Check = mockAuction.getBid(bidId1);
            emit log_named_uint('Bid1 startBlock', bid1Check.startBlock);

            uint256 bid1Spent;
            {
                uint256 ownerBalance = bid1Check.owner.balance;

                if (_sweepEarly && expectReverts) {
                    vm.expectRevert();
                }
                mockAuction.exitPartiallyFilledBid(bidId1, bid1Check.startBlock, 4);
                uint256 refund = bid1Check.owner.balance - ownerBalance;
                bid1Spent = (bid1Check.amountQ96 >> FixedPoint96.RESOLUTION) - refund;
                emit log_named_decimal_uint('Bid1 spent', bid1Spent, 18);
                emit log_named_decimal_uint('Bid1 refund', refund, 18);
            }

            // Exit bid2: at clearing price (not outbid), so outbidBlock = 0
            Bid memory bid2Check = mockAuction.getBid(bidId2);
            uint256 bid2Spent;
            {
                uint256 ownerBalance = bid2Check.owner.balance;
                if (_sweepEarly && expectReverts) {
                    vm.expectRevert();
                }
                mockAuction.exitBid(bidId2);
                uint256 refund = bid2Check.owner.balance - ownerBalance;
                bid2Spent = (bid2Check.amountQ96 >> FixedPoint96.RESOLUTION) - refund;
                emit log_named_decimal_uint('Bid2 spent', bid2Spent, 18);
                emit log_named_decimal_uint('Bid2 refund', refund, 18);
            }

            // Check filled amounts after exit
            Bid memory bid1 = mockAuction.getBid(bidId1);
            Bid memory bid2 = mockAuction.getBid(bidId2);

            emit log_string('');
            emit log_string('=== ACCOUNTING BUG DEMONSTRATION ===');
            emit log_named_decimal_uint('B1 filled (FINAL)', bid1.tokensFilled, 18);
            emit log_named_decimal_uint('B2 filled (FINAL)', bid2.tokensFilled, 18);
            uint256 sumOfIndividualFills = bid1.tokensFilled + bid2.tokensFilled;
            emit log_named_decimal_uint('Sum of individual token fills', sumOfIndividualFills, 18);
            emit log_named_decimal_uint('Sum of individual currency spent', bid1Spent + bid2Spent, 18);
            emit log_named_decimal_uint('Total raised (reported)', raised, 18);
            int256 discrepancy = int256(raised) - int256(bid1Spent + bid2Spent);
            emit log_named_decimal_int('DISCREPANCY', discrepancy, 18);
            require(raised <= bid1Spent + bid2Spent, 'expectedCurrencyRaised is greater than actual currency raised');

            emit log_string('=== END ===');
        }

        {
            vm.roll(mockAuction.claimBlock());
            emit log('==================== CLAIM TOKENS ====================');
            Bid memory bid1 = mockAuction.getBid(bidId1);
            Bid memory bid2 = mockAuction.getBid(bidId2);

            assertEq(token.balanceOf(address(bid1.owner)), 0);
            assertEq(token.balanceOf(address(bid2.owner)), 0);

            if (_sweepEarly && expectReverts) {
                vm.expectRevert();
            }
            mockAuction.claimTokens(bidId1);

            if (_sweepEarly && expectReverts) {
                vm.expectRevert();
            }
            mockAuction.claimTokens(bidId2);

            emit log_named_decimal_uint('B1 owner token balance', token.balanceOf(address(bid1.owner)), 18);
            emit log_named_decimal_uint('B2 owner token balance', token.balanceOf(address(bid2.owner)), 18);
        }
    }

    function _sweep(bool _sweepEarly) public {
        // Sweep.
        emit log_string('==================== SWEEP ====================');

        emit log_named_decimal_uint('Token Balance of auction   ', token.balanceOf(address(mockAuction)), 18);
        emit log_named_decimal_uint('Currency Balance of auction', address(mockAuction).balance, 18);

        // Sweep
        emit log_string('Sweeping unsold tokens and currency');
        mockAuction.sweepUnsoldTokens();

        if (!_sweepEarly && expectReverts) {
            vm.expectRevert();
        }
        mockAuction.sweepCurrency();

        emit log_named_decimal_uint('Token Balance of auction   ', token.balanceOf(address(mockAuction)), 18);
        emit log_named_decimal_uint('Currency Balance of auction', address(mockAuction).balance, 18);
    }

    function _finalBalances(string memory _message) internal {
        emit log('');
        emit log(_message);

        emit log_named_decimal_uint('Token Balance of auction             ', token.balanceOf(address(mockAuction)), 18);
        emit log_named_decimal_uint('Currency Balance of auction          ', address(mockAuction).balance, 18);

        emit log_named_decimal_uint(
            'Token Balance of auction recipient   ', token.balanceOf(address(mockAuction.tokensRecipient())), 18
        );
        emit log_named_decimal_uint(
            'Currency Balance of auction recipient', address(mockAuction.fundsRecipient()).balance, 18
        );

        emit log_named_decimal_uint('Token Balance of alice               ', token.balanceOf(address(alice)), 18);
        emit log_named_decimal_uint('Currency Balance of alice            ', address(alice).balance, 18);

        emit log_named_decimal_uint('Token Balance of bob                 ', token.balanceOf(address(bob)), 18);
        emit log_named_decimal_uint('Currency Balance of bob              ', address(bob).balance, 18);

        emit log(_message);
    }

    function _setupLargeTickAuction() internal {
        uint64 startBlock = uint64(block.number);
        uint64 endBlock = startBlock + 40;

        // Large tick spacing - price jumps: $10, $20, $30
        uint256 largeTickSpacing = 10 << FixedPoint96.RESOLUTION;
        tick10 = 10 * FixedPoint96.Q96;
        tick20 = 20 * FixedPoint96.Q96;
        tick30 = 30 * FixedPoint96.Q96;

        AuctionParameters memory testParams = params;
        testParams.startBlock = startBlock;
        testParams.endBlock = endBlock;
        testParams.auctionStepsData = AuctionStepsBuilder.init().addStep(250e3, 40);
        testParams.tickSpacing = largeTickSpacing;
        testParams.floorPrice = tick10;

        mockAuction = new MockContinuousClearingAuction(address(token), TOTAL_SUPPLY, testParams);
        token.mint(address(mockAuction), TOTAL_SUPPLY);
        mockAuction.onTokensReceived();
    }
}
