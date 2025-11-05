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

contract Temp is AuctionBaseTest {
    using AuctionParamsBuilder for AuctionParameters;
    using AuctionStepsBuilder for bytes;
    using ValueX7Lib for *;

    address private charlie;

    // Storage variables to avoid stack too deep
    uint256 private tick10;
    uint256 private tick20;
    uint256 private tick30;
    uint256 private tick40;
    uint256 private tick3000;
    MockContinuousClearingAuction private mockAuction;

    uint256 private bidId2;

    bool internal expectReverts = false;

    uint128 private TOTAL_SUPPLY_POC = 1e30;

    function setUp() public {
        setUpAuction();
        bob = makeAddr('bob');
        charlie = makeAddr('charlie');

        _setupLargeTickAuction();
    }

    function test_largeTickSpacing_causesBurnAuction_lateSweep() public {
        _test_largeTickSpacing_causesBurnAuction(false, TOTAL_SUPPLY_POC * 999 / 1000 - 1009e18 - 1);
    }

    function test_showcaseIssue() public {
        _test_largeTickSpacing_causesBurnAuction(false, 485_132_254_581_071_629_498_241_743_687);
    }

    function test_atClearingPrice() public {
        _test_largeTickSpacing_causesBurnAuction(false, TOTAL_SUPPLY_POC);
    }

    function test_search(uint128 amount) public {
        _test_largeTickSpacing_causesBurnAuction(false, amount);
    }

    function _test_largeTickSpacing_causesBurnAuction(bool _sweepEarly, uint128 amount) public {
        AuctionStep memory step = mockAuction.step();

        // PERIOD 2: Add second bid at tick30
        emit log_named_uint('Bid2 block', block.number);
        uint128 currency2 = inputAmountForTokens(amount, tick40);
        emit log_named_decimal_uint('Currency2 calculated', currency2, 18);
        vm.deal(address(this), currency2);
        bidId2 = mockAuction.submitBid{value: currency2}(tick40, currency2, alice, tick10, bytes(''));
        {
            Bid memory bid2 = mockAuction.getBid(bidId2);
            emit log_named_decimal_uint('B2, maxPrice', bid2.maxPrice, 18);
        }

        vm.roll(block.number + 1);
        emit log_named_uint('Cp2, block', block.number);
        Checkpoint memory cp2 = mockAuction.checkpoint();
        // Fine to do mockAuction.currencyRaised since it uses the latest checkpoint
        emit log_named_decimal_uint('Cp2, raised', mockAuction.currencyRaised(), 18);
        emit log_named_decimal_uint('Cp2, Price after second bid', cp2.clearingPrice, 18);
        emit log_named_decimal_uint('Cp2, Cumulative MPS', cp2.cumulativeMps, 5);
        emit log_named_decimal_uint('Demand above clearing', mockAuction.sumCurrencyDemandAboveClearingQ96(), 18);
        emit log('');

        emit log_named_decimal_uint('total_currency', currency2, 18);

        {
            vm.roll(block.number + 1);
            Checkpoint memory cp3 = mockAuction.checkpoint();
            // Fine to do mockAuction.currencyRaised since it uses the latest checkpoint
            emit log_named_decimal_uint('Cp3, raised', mockAuction.currencyRaised(), 18);
            emit log_named_decimal_uint('Cp3, Price after third checkpoint', cp3.clearingPrice, 18);
            emit log_named_decimal_uint('Cp3, Cumulative MPS', cp3.cumulativeMps, 5);
        }

        // Roll to end
        vm.roll(step.endBlock);
        Checkpoint memory finalCheckpoint = mockAuction.checkpoint();

        emit log_named_uint('Final checkpoint block', block.number);

        bool graduated = mockAuction.isGraduated();
        uint256 raised = ValueX7.unwrap(mockAuction.currencyRaisedQ96_X7());

        emit log('==================== FINAL CHECKPOINT ====================');
        emit log_named_decimal_uint(
            'r                 ',
            31_659_573_708_723_542_911_623_075_901_480_000_000_000_000_000_000_000_000_000_000_000_000,
            18
        );
        emit log_named_decimal_uint('Raised            ', raised / 1e7 / FixedPoint96.Q96, 18);
        emit log_named_decimal_uint('Balance of auction', address(mockAuction).balance, 18);
        assertGe(address(mockAuction).balance, raised / 1e7 / FixedPoint96.Q96);

        emit log_named_decimal_uint('Cumulative MPS          ', finalCheckpoint.cumulativeMps, 5);
        emit log_named_decimal_uint('Cumulative MPS per price', finalCheckpoint.cumulativeMpsPerPrice, 32);
        emit log_named_decimal_uint('Price', finalCheckpoint.clearingPrice, 18);
        emit log_named_decimal_uint('P-10 ', tick10, 18);
        emit log_named_decimal_uint('P-20 ', tick20, 18);
        emit log_named_decimal_uint('P-30 ', tick30, 18);
        emit log_named_decimal_uint('P-40 ', tick40, 18);
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
        Checkpoint memory finalCheckpoint = mockAuction.checkpoint();
        uint256 raised = mockAuction.currencyRaised();

        {
            uint256 totalRefunded;
            emit log('==================== EXITING BIDS ====================');

            // Exit bid2: at clearing price (not outbid), so outbidBlock = 0
            Bid memory bid2Check = mockAuction.getBid(bidId2);
            {
                uint256 ownerBalance = bid2Check.owner.balance;
                if (_sweepEarly && expectReverts) {
                    vm.expectRevert();
                }
                if (bid2Check.maxPrice > finalCheckpoint.clearingPrice) {
                    mockAuction.exitBid(bidId2);
                } else {
                    mockAuction.exitPartiallyFilledBid(bidId2, bid2Check.startBlock, 0);
                }
                emit log_named_decimal_uint('Bid2 refund', bid2Check.owner.balance - ownerBalance, 18);
                totalRefunded += bid2Check.owner.balance - ownerBalance;
            }

            // Check filled amounts after exit
            Bid memory bid2 = mockAuction.getBid(bidId2);

            emit log_string('');
            emit log_string('=== ACCOUNTING BUG DEMONSTRATION ===');
            emit log_named_decimal_uint('B2 filled (FINAL)', bid2.tokensFilled, 18);
            emit log_named_decimal_uint('B2 amount (FINAL)', bid2.amountQ96, 18);
            uint256 sumOfIndividualFills = bid2.tokensFilled;
            uint256 sumOfIndividualAmounts = (bid2.amountQ96) >> FixedPoint96.RESOLUTION;
            emit log_named_decimal_uint('Sum of individual fills', sumOfIndividualFills, 18);
            emit log_named_decimal_uint('Sum of individual amounts', sumOfIndividualAmounts, 18);
            emit log_named_decimal_uint('Total refunded', totalRefunded, 18);
            emit log_named_decimal_uint('Actual raised (calculated)', sumOfIndividualAmounts - totalRefunded, 18);
            emit log_named_decimal_uint('Total raised (reported)', raised, 18);
            emit log_named_decimal_int(
                'Discrepancy', int256(sumOfIndividualAmounts - totalRefunded) - int256(raised), 18
            );

            emit log_string('=== END ===');
        }

        {
            vm.roll(mockAuction.claimBlock());
            emit log('==================== CLAIM TOKENS ====================');
            Bid memory bid2 = mockAuction.getBid(bidId2);

            assertEq(token.balanceOf(address(bid2.owner)), 0);

            if (_sweepEarly && expectReverts) {
                vm.expectRevert();
            }

            if (bid2.tokensFilled > 0) {
                emit log_string('Claiming tokens');
                mockAuction.claimTokens(bidId2);
            } else {
                emit log_string('No tokens to claim');
            }

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

        uint256 alicePaid = mockAuction.getBid(bidId2).amountQ96 - address(alice).balance;
        emit log_named_decimal_uint('Token Balance of alice               ', token.balanceOf(address(alice)), 18);
        emit log_named_decimal_uint('Currency Balance of alice            ', address(alice).balance, 18);
        emit log_named_decimal_uint('Alice paid                           ', alicePaid, 18);
        emit log(_message);
    }

    function _setupLargeTickAuction() internal {
        uint64 startBlock = uint64(block.number);
        uint64 endBlock = startBlock + 1000;

        // Large tick spacing - price jumps: $10, $20, $30
        uint256 largeTickSpacing = 10 << FixedPoint96.RESOLUTION;
        tick10 = 10 * FixedPoint96.Q96;
        tick20 = 20 * FixedPoint96.Q96;
        tick30 = 30 * FixedPoint96.Q96;
        tick40 = 40 * FixedPoint96.Q96;

        tick3000 = 3000 * FixedPoint96.Q96;

        AuctionParameters memory testParams = params;
        testParams.startBlock = startBlock;
        testParams.endBlock = endBlock;
        testParams.claimBlock = endBlock;
        testParams.auctionStepsData = AuctionStepsBuilder.init().addStep(10_000, 1000);
        testParams.tickSpacing = largeTickSpacing;
        testParams.floorPrice = tick10;

        mockAuction = new MockContinuousClearingAuction(address(token), TOTAL_SUPPLY_POC, testParams);
        token.mint(address(mockAuction), TOTAL_SUPPLY_POC);
        mockAuction.onTokensReceived();
    }
}
