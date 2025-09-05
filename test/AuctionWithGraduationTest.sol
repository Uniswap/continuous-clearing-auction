// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Auction} from '../src/Auction.sol';
import {AuctionParameters} from '../src/interfaces/IAuction.sol';
import {ITickStorage} from '../src/interfaces/ITickStorage.sol';
import {ITokenCurrencyStorage} from '../src/interfaces/ITokenCurrencyStorage.sol';
import {FixedPoint96} from '../src/libraries/FixedPoint96.sol';
import {AuctionBaseTest} from './utils/AuctionBaseTest.sol';
import {AuctionParamsBuilder} from './utils/AuctionParamsBuilder.sol';
import {AuctionStepsBuilder} from './utils/AuctionStepsBuilder.sol';
import {MockFundsRecipient} from './utils/MockFundsRecipient.sol';
import {TokenHandler} from './utils/TokenHandler.sol';
import {Test} from 'forge-std/Test.sol';

contract AuctionWithGraduationTest is AuctionBaseTest {
    using AuctionParamsBuilder for AuctionParameters;
    using AuctionStepsBuilder for bytes;

    constructor() AuctionBaseTest(100, 100, 1000 << FixedPoint96.RESOLUTION, 1000e18) {}

    function _createAuction() internal override returns (Auction) {
        alice = makeAddr('alice');
        tokensRecipient = makeAddr('tokensRecipient');
        fundsRecipient = makeAddr('fundsRecipient');
        mockFundsRecipient = new MockFundsRecipient();

        auctionStepsData = AuctionStepsBuilder.init().addStep(100e3, 50).addStep(100e3, 50);
        params = AuctionParamsBuilder.init().withCurrency(ETH_SENTINEL).withFloorPrice(FLOOR_PRICE).withTickSpacing(
            TICK_SPACING
        ).withValidationHook(address(0)).withTokensRecipient(tokensRecipient).withFundsRecipient(fundsRecipient)
            .withStartBlock(block.number).withEndBlock(block.number + AUCTION_DURATION).withClaimBlock(
            block.number + AUCTION_DURATION + 10
        ).withAuctionStepsData(auctionStepsData);

        // Add a threshold of 75%
        params = params.withGraduationThresholdMps(75e5);

        // Expect the floor price tick to be initialized
        vm.expectEmit(true, true, true, true);
        emit ITickStorage.TickInitialized(tickNumberToPriceX96(1));
        Auction _auction = new Auction(address(token), TOTAL_SUPPLY, params);

        token.mint(address(_auction), TOTAL_SUPPLY);
        return _auction;
    }

    function test_sweepCurrency_withFundsRecipientData_revertsWithReason() public {
        // Set up auction with MockFundsRecipient and callback data that will revert
        bytes memory revertReason = bytes('Custom revert reason');
        params = params.withGraduationThresholdMps(30e5).withFundsRecipient(address(mockFundsRecipient))
            .withFundsRecipientData(abi.encodeWithSignature('revertWithReason(bytes)', revertReason));

        Auction auctionWithCallback = new Auction(address(token), TOTAL_SUPPLY, params);
        token.mint(address(auctionWithCallback), TOTAL_SUPPLY);

        // Submit a bid for 50% of supply (above 30% threshold)
        uint128 halfSupply = TOTAL_SUPPLY / 2;
        uint128 inputAmount = inputAmountForTokens(halfSupply, tickNumberToPriceX96(2));
        auctionWithCallback.submitBid{value: getMsgValue(inputAmount)}(
            tickNumberToPriceX96(2), true, inputAmount, alice, tickNumberToPriceX96(1), bytes('')
        );

        vm.roll(auctionWithCallback.endBlock());
        // Update the lastCheckpoint to register the auction as graduated
        auctionWithCallback.checkpoint();

        // The callback should revert with the custom reason
        vm.prank(address(mockFundsRecipient));
        vm.expectRevert('Custom revert reason');
        auctionWithCallback.sweepCurrency();
    }

    function test_sweepCurrency_withFundsRecipientData_revertsWithoutReason() public {
        // Set up auction with MockFundsRecipient and callback data that will revert without reason
        params = params.withGraduationThresholdMps(30e5).withFundsRecipient(address(mockFundsRecipient))
            .withFundsRecipientData(abi.encodeWithSignature('revertWithoutReason()'));

        Auction auctionWithCallback = new Auction(address(token), TOTAL_SUPPLY, params);
        token.mint(address(auctionWithCallback), TOTAL_SUPPLY);

        // Submit a bid for 50% of supply (above 30% threshold)
        uint128 halfSupply = TOTAL_SUPPLY / 2;
        uint128 inputAmount = inputAmountForTokens(halfSupply, tickNumberToPriceX96(2));
        auctionWithCallback.submitBid{value: getMsgValue(inputAmount)}(
            tickNumberToPriceX96(2), true, inputAmount, alice, tickNumberToPriceX96(1), bytes('')
        );

        vm.roll(auctionWithCallback.endBlock());
        // Update the lastCheckpoint to register the auction as graduated
        auctionWithCallback.checkpoint();

        // The callback should revert without a reason
        vm.prank(address(mockFundsRecipient));
        vm.expectRevert();
        auctionWithCallback.sweepCurrency();
    }

    function test_sweepCurrency_withFundsRecipientData_EOA_doesNotCall() public {
        // Set up auction with EOA recipient and callback data (should not call)
        params = params.withGraduationThresholdMps(30e5).withFundsRecipient(fundsRecipient) // EOA
            .withFundsRecipientData(abi.encodeWithSignature('someFunction()'));

        Auction auctionWithCallback = new Auction(address(token), TOTAL_SUPPLY, params);
        token.mint(address(auctionWithCallback), TOTAL_SUPPLY);

        // Submit a bid for 50% of supply (above 30% threshold)
        uint128 halfSupply = TOTAL_SUPPLY / 2;
        uint128 inputAmount = inputAmountForTokens(halfSupply, tickNumberToPriceX96(2));
        auctionWithCallback.submitBid{value: getMsgValue(inputAmount)}(
            tickNumberToPriceX96(2), true, inputAmount, alice, tickNumberToPriceX96(1), bytes('')
        );

        vm.roll(auctionWithCallback.endBlock());
        // Update the lastCheckpoint to register the auction as graduated
        auctionWithCallback.checkpoint();

        // Should succeed without calling the EOA (EOAs have no code)
        vm.prank(fundsRecipient);
        vm.expectEmit(true, true, true, true);
        emit ITokenCurrencyStorage.CurrencySwept(fundsRecipient, inputAmount);
        auctionWithCallback.sweepCurrency();

        // Verify funds were transferred
        assertEq(fundsRecipient.balance, inputAmount);
    }

    function test_sweepCurrency_withFundsRecipientData_contractRecipientSucceedsWithValidData() public {
        // Create a more complex callback scenario with a contract recipient
        MockFundsRecipient contractRecipient = new MockFundsRecipient();

        // Set up auction with contract recipient and valid callback data
        bytes memory callbackData = abi.encodeWithSignature('fallback()');
        params = params.withGraduationThresholdMps(30e5).withFundsRecipient(address(contractRecipient))
            .withFundsRecipientData(callbackData);

        Auction auctionWithCallback = new Auction(address(token), TOTAL_SUPPLY, params);
        token.mint(address(auctionWithCallback), TOTAL_SUPPLY);

        // Submit a bid for 50% of supply (above 30% threshold)
        uint128 halfSupply = TOTAL_SUPPLY / 2;
        uint128 inputAmount = inputAmountForTokens(halfSupply, tickNumberToPriceX96(2));
        auctionWithCallback.submitBid{value: getMsgValue(inputAmount)}(
            tickNumberToPriceX96(2), true, inputAmount, alice, tickNumberToPriceX96(1), bytes('')
        );

        vm.roll(auctionWithCallback.endBlock());
        // Update the lastCheckpoint to register the auction as graduated
        auctionWithCallback.checkpoint();

        // Verify the contract receives funds and the callback is executed
        uint256 balanceBefore = getCurrencyBalance(address(contractRecipient));

        // Expect the callback to be made with the specified data
        vm.expectCall(address(contractRecipient), callbackData);

        vm.prank(address(contractRecipient));
        vm.expectEmit(true, true, true, true);
        emit ITokenCurrencyStorage.CurrencySwept(address(contractRecipient), inputAmount);
        auctionWithCallback.sweepCurrency();

        // Verify funds were transferred
        assertEq(getCurrencyBalance(address(contractRecipient)), balanceBefore + inputAmount);
    }

    function test_sweepCurrency_withFundsRecipientData_multipleCallsWithDifferentData() public {
        // Test that the data is correctly stored and used
        bytes memory firstCallData = abi.encodeWithSignature('fallback()');
        params = params.withGraduationThresholdMps(30e5).withFundsRecipient(address(mockFundsRecipient))
            .withFundsRecipientData(firstCallData);

        Auction firstAuction = new Auction(address(token), TOTAL_SUPPLY, params);
        token.mint(address(firstAuction), TOTAL_SUPPLY);

        // Second auction with different callback data
        bytes memory secondCallData = abi.encodeWithSignature('revertWithReason(bytes)', bytes('Should revert'));
        AuctionParameters memory params2 = params.withFundsRecipientData(secondCallData);

        Auction secondAuction = new Auction{salt: bytes32(uint256(2))}(address(token), TOTAL_SUPPLY, params2);
        token.mint(address(secondAuction), TOTAL_SUPPLY);

        // Submit bids to both auctions
        uint128 halfSupply = TOTAL_SUPPLY / 2;
        uint128 inputAmount = inputAmountForTokens(halfSupply, tickNumberToPriceX96(2));

        firstAuction.submitBid{value: getMsgValue(inputAmount)}(
            tickNumberToPriceX96(2), true, inputAmount, alice, tickNumberToPriceX96(1), bytes('')
        );

        secondAuction.submitBid{value: getMsgValue(inputAmount)}(
            tickNumberToPriceX96(2), true, inputAmount, alice, tickNumberToPriceX96(1), bytes('')
        );

        vm.roll(firstAuction.endBlock());
        // Update the lastCheckpoint to register the auction as graduated
        firstAuction.checkpoint();

        vm.roll(secondAuction.endBlock());
        // Update the lastCheckpoint to register the auction as graduated
        secondAuction.checkpoint();

        // First auction should succeed - expect the callback to be made
        vm.expectCall(address(mockFundsRecipient), firstCallData);
        vm.prank(address(mockFundsRecipient));
        firstAuction.sweepCurrency();

        // Second auction should revert with the expected message
        vm.prank(address(mockFundsRecipient));
        vm.expectRevert('Should revert');
        secondAuction.sweepCurrency();
    }

    function test_sweepCurrency_withFundsRecipientData_callsRecipient() public {
        // Set up auction with MockFundsRecipient and callback data
        bytes memory callbackData = abi.encodeWithSignature('fallback()');
        params = params.withGraduationThresholdMps(30e5).withFundsRecipient(address(mockFundsRecipient))
            .withFundsRecipientData(callbackData);

        Auction auctionWithCallback = new Auction(address(token), TOTAL_SUPPLY, params);
        token.mint(address(auctionWithCallback), TOTAL_SUPPLY);

        // Submit a bid for 50% of supply (above 30% threshold)
        uint128 halfSupply = TOTAL_SUPPLY / 2;
        uint128 inputAmount = inputAmountForTokens(halfSupply, tickNumberToPriceX96(2));
        auctionWithCallback.submitBid{value: getMsgValue(inputAmount)}(
            tickNumberToPriceX96(2), true, inputAmount, alice, tickNumberToPriceX96(1), bytes('')
        );

        vm.roll(auctionWithCallback.endBlock());
        // Update the lastCheckpoint to register the auction as graduated
        auctionWithCallback.checkpoint();

        if (auction.fundsRecipientData().length > 0 && address(auction.fundsRecipient()).code.length > 0) {
            // Expect the callback to be made with the specified data
            vm.expectCall(address(mockFundsRecipient), callbackData);
        }
        vm.prank(address(mockFundsRecipient));
        vm.expectEmit(true, true, true, true);
        emit ITokenCurrencyStorage.CurrencySwept(address(mockFundsRecipient), inputAmount);
        auctionWithCallback.sweepCurrency();

        // Verify funds were transferred
        assertEq(getCurrencyBalance(address(mockFundsRecipient)), inputAmount);
    }

    function test_sweepCurrency_thenSweepTokens_graduated_succeeds() public {
        // Create an auction with graduation threshold (40%)
        params = params.withGraduationThresholdMps(40e5);

        Auction auctionWithThreshold = new Auction(address(token), TOTAL_SUPPLY, params);
        token.mint(address(auctionWithThreshold), TOTAL_SUPPLY);

        // Submit a bid for 70% of supply (above threshold)
        uint128 soldAmount = (TOTAL_SUPPLY * 70) / 100;
        uint128 inputAmount = inputAmountForTokens(soldAmount, tickNumberToPriceX96(1));
        auctionWithThreshold.submitBid{value: getMsgValue(inputAmount)}(
            tickNumberToPriceX96(2), true, inputAmount, alice, tickNumberToPriceX96(1), bytes('')
        );

        vm.roll(auctionWithThreshold.endBlock());
        // Update the lastCheckpoint to register the auction as graduated
        auctionWithThreshold.checkpoint();

        // Sweep currency first (should succeed as graduated)
        uint128 expectedCurrencyRaised = inputAmountForTokens(soldAmount, tickNumberToPriceX96(1));
        vm.prank(fundsRecipient);
        vm.expectEmit(true, true, true, true);
        emit ITokenCurrencyStorage.CurrencySwept(fundsRecipient, expectedCurrencyRaised);
        auctionWithThreshold.sweepCurrency();

        // Then sweep unsold tokens
        uint128 expectedUnsoldTokens = TOTAL_SUPPLY - soldAmount;
        vm.expectEmit(true, true, true, true);
        emit ITokenCurrencyStorage.TokensSwept(tokensRecipient, expectedUnsoldTokens);
        auctionWithThreshold.sweepUnsoldTokens();

        // Verify transfers
        assertEq(fundsRecipient.balance, expectedCurrencyRaised);
        assertEq(token.balanceOf(tokensRecipient), expectedUnsoldTokens);
    }

    function test_sweepTokens_notGraduated_cannotSweepCurrency() public {
        // Create an auction with high graduation threshold (80%)
        params = params.withGraduationThresholdMps(80e5);

        Auction auctionWithThreshold = new Auction(address(token), TOTAL_SUPPLY, params);
        token.mint(address(auctionWithThreshold), TOTAL_SUPPLY);

        // Submit a bid for only 20% of supply (below 80% threshold)
        uint128 smallAmount = TOTAL_SUPPLY / 5;
        uint128 inputAmount = inputAmountForTokens(smallAmount, tickNumberToPriceX96(1));
        auctionWithThreshold.submitBid{value: getMsgValue(inputAmount)}(
            tickNumberToPriceX96(2), true, inputAmount, alice, tickNumberToPriceX96(1), bytes('')
        );

        vm.roll(auctionWithThreshold.endBlock());
        // Update the lastCheckpoint
        auctionWithThreshold.checkpoint();

        // Can sweep tokens (returns all since not graduated)
        vm.expectEmit(true, true, true, true);
        emit ITokenCurrencyStorage.TokensSwept(tokensRecipient, TOTAL_SUPPLY);
        auctionWithThreshold.sweepUnsoldTokens();

        // Cannot sweep currency (not graduated)
        vm.prank(fundsRecipient);
        vm.expectRevert(ITokenCurrencyStorage.NotGraduated.selector);
        auctionWithThreshold.sweepCurrency();
    }
}
