// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Auction} from '../src/Auction.sol';
import {AuctionParameters, IAuction} from '../src/interfaces/IAuction.sol';
import {ITickStorage} from '../src/interfaces/ITickStorage.sol';
import {FixedPoint96} from '../src/libraries/FixedPoint96.sol';
import {AuctionBaseTest} from './utils/AuctionBaseTest.sol';
import {AuctionParamsBuilder} from './utils/AuctionParamsBuilder.sol';
import {AuctionStepsBuilder} from './utils/AuctionStepsBuilder.sol';
import {MockFundsRecipient} from './utils/MockFundsRecipient.sol';

import {MockValidationHook} from './utils/MockValidationHook.sol';
import {TokenHandler} from './utils/TokenHandler.sol';
import {Test} from 'forge-std/Test.sol';

contract AuctionNativeCurrencyTest is AuctionBaseTest {
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

        // Expect the floor price tick to be initialized
        vm.expectEmit(true, true, true, true);
        emit ITickStorage.TickInitialized(tickNumberToPriceX96(1));
        Auction nativeCurrencyAuction = new Auction(address(token), TOTAL_SUPPLY, params);

        token.mint(address(nativeCurrencyAuction), TOTAL_SUPPLY);
        return nativeCurrencyAuction;
    }

    function test_submitBid_exactInMsgValue_revertsWithInvalidAmount() public {
        vm.expectRevert(IAuction.InvalidAmount.selector);
        // msg.value should be 1000e18
        auction.submitBid{value: 2000e18}(
            tickNumberToPriceX96(2), true, 1000e18, alice, tickNumberToPriceX96(1), bytes('')
        );
    }

    function test_submitBid_exactInZeroMsgValue_revertsWithInvalidAmount() public {
        vm.expectRevert(IAuction.InvalidAmount.selector);
        auction.submitBid{value: 0}(tickNumberToPriceX96(2), true, 1000e18, alice, tickNumberToPriceX96(1), bytes(''));
    }

    function test_submitBid_exactOutMsgValue_revertsWithInvalidAmount() public {
        vm.expectRevert(IAuction.InvalidAmount.selector);
        // msg.value should be 2 * 1000e18
        auction.submitBid{value: 1000e18}(
            tickNumberToPriceX96(2), false, 1000e18, alice, tickNumberToPriceX96(1), bytes('')
        );
    }

    /// forge-config: default.isolate = true
    /// forge-config: ci.isolate = true
    function test_submitBid_withValidationHook_callsValidationHook_gas() public {
        // Create a mock validation hook
        MockValidationHook validationHook = new MockValidationHook();

        // Create auction parameters with the validation hook
        params = params.withValidationHook(address(validationHook));

        Auction testAuction = new Auction(address(token), TOTAL_SUPPLY, params);
        token.mint(address(testAuction), TOTAL_SUPPLY);

        // Submit a bid with hook data to trigger the validation hook
        uint256 bidId = testAuction.submitBid{value: getMsgValue(inputAmountForTokens(100e18, tickNumberToPriceX96(2)))}(
            tickNumberToPriceX96(2),
            true,
            inputAmountForTokens(100e18, tickNumberToPriceX96(2)),
            alice,
            tickNumberToPriceX96(1),
            bytes('hook data')
        );
        vm.snapshotGasLastCall('submitBid_withValidationHook');

        assertEq(bidId, 0);
    }
}
