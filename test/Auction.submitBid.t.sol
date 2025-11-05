// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IContinuousClearingAuction} from '../src/interfaces/IContinuousClearingAuction.sol';
import {AuctionParameters} from '../src/interfaces/IContinuousClearingAuction.sol';
import {Bid, BidLib} from '../src/libraries/BidLib.sol';
import {Checkpoint} from '../src/libraries/CheckpointLib.sol';
import {ConstantsLib} from '../src/libraries/ConstantsLib.sol';
import {FixedPoint96} from '../src/libraries/FixedPoint96.sol';
import {ValueX7} from '../src/libraries/ValueX7Lib.sol';
import {AuctionBaseTest} from './utils/AuctionBaseTest.sol';
import {FuzzBid, FuzzDeploymentParams} from './utils/FuzzStructs.sol';
import {console2} from 'forge-std/console2.sol';
import {FixedPointMathLib} from 'solady/utils/FixedPointMathLib.sol';

contract AuctionSubmitBidTest is AuctionBaseTest {
    using BidLib for *;

    /// forge-config: default.fuzz.runs = 1000
    function test_submitBid_exactIn_succeeds(FuzzDeploymentParams memory _deploymentParams, FuzzBid[] memory _bids)
        public
        setUpAuctionFuzz(_deploymentParams)
        setUpBidsFuzz(_bids)
        givenAuctionHasStarted
        givenFullyFundedAccount
    {
        uint256 expectedBidId;
        for (uint256 i = 0; i < _bids.length; i++) {
            (bool bidPlaced, uint256 bidId) = helper__trySubmitBid(expectedBidId, _bids[i], alice);
            if (bidPlaced) expectedBidId++;

            helper__maybeRollToNextBlock(i);
        }
    }

    function test_submitBid_revertsWithInvalidBidPriceTooHigh(
        FuzzDeploymentParams memory _deploymentParams,
        uint256 _maxPrice
    ) public setUpAuctionFuzz(_deploymentParams) givenAuctionHasStarted givenFullyFundedAccount {
        // Assume there is at least one tick that is above the MAX_BID_PRICE and type(uint256).max
        vm.assume(auction.MAX_BID_PRICE() < helper__roundPriceDownToTickSpacing(type(uint256).max, params.tickSpacing));
        _maxPrice = _bound(
            _maxPrice,
            helper__roundPriceUpToTickSpacing(auction.MAX_BID_PRICE() + 1, params.tickSpacing),
            type(uint256).max
        );
        _maxPrice = helper__roundPriceDownToTickSpacing(_maxPrice, params.tickSpacing);
        vm.expectRevert(IContinuousClearingAuction.InvalidBidPriceTooHigh.selector);
        auction.submitBid{value: 1}(_maxPrice, 1, alice, params.floorPrice, bytes(''));
    }

    // Rationale:
    // This test is to verify that the auction will prevent itself from getting into a state where
    // the unchecked math in Auction.sol:_sellTokensAtClearingPrice 202-203 below
    //          unchecked {
    //              totalCurrencyForDeltaQ96X7 = (uint256(TOTAL_SUPPLY) * priceQ96) * deltaMpsU;
    //          }
    // would cause an overflow.
    // To hit this case, we create an auction with a very small total supply and submit bids at the
    // maximum allowable price.
    function test_WhenBidMaxPriceWouldCauseTotalSupplyTimesMaxPriceTimesMPSToOverflow(FuzzDeploymentParams memory _deploymentParams)
        public
        givenFullyFundedAccount
    {
        // it does not overflow in TOTAL_SUPPLY * priceQ96 * ConstantsLib.MPS

        // Given that the v4 max tick price is lower bounded by 2^223, that is the max, max bid price
        // for higher totalSupply values the max price will be lower
        // roughly the math works out to (s2^256 - 1) / 2^223 * 2^24 < 2^9 = 512
        // and accounting for rounding, etc. we find that the boundary is at 429
        _deploymentParams.totalSupply = 429;
        vm.assume(_deploymentParams.auctionParams.floorPrice > 2);
        // Set tick spacing to 3 for this test since we know that v4 max tick is divisible by 3
        _deploymentParams.auctionParams.tickSpacing = 3;
        _deploymentParams.numberOfSteps = 1;
        setUpAuction(_deploymentParams);
        // Sometimes tickSpacing gets bounded to 2
        vm.assume(auction.tickSpacing() == 3);

        // Assert that the auction was setup correctly
        assertTrue(auction.startBlock() + 1 == auction.endBlock(), 'start block + 1 should be equal to end block');

        uint256 maxPrice = auction.MAX_BID_PRICE();
        assertEq(maxPrice, ConstantsLib.MAX_BID_PRICE, 'maxPrice is not equal to ConstantsLib.MAX_BID_PRICE');
        maxPrice = helper__roundPriceDownToTickSpacing(maxPrice, params.tickSpacing);
        // Assert that we didn't fall below after rounding down to tick spacing
        assertEq(
            maxPrice,
            auction.MAX_BID_PRICE(),
            'maxPrice is not equal to MAX_BID_PRICE after rounding down to tick spacing'
        );

        // Roll to the last block to maximize `deltaMpsU` term to be 1e7
        vm.roll(auction.endBlock() - 1);
        uint256 totalSupply = auction.totalSupply();
        uint256 bidAmount = FixedPointMathLib.fullMulDivUp(1, maxPrice, FixedPoint96.Q96);
        assertLt(bidAmount, type(uint128).max, 'bidAmount would cause overflow');

        // with the high max price, we can only submit bids in small increments since bidAmount is uint128
        // submit all except for one to put us at the boundary of overflow
        for (uint256 i = 0; i < totalSupply; i++) {
            auction.submitBid{value: bidAmount}(maxPrice, uint128(bidAmount), alice, params.floorPrice, bytes(''));
        }

        // Assert that the next bid for 1 token unit would cause overflow, but it is caught in submit bid
        // The amount is 1, the smallest amount of tokens that can be bid for.
        // The maxPrice is still valid because maxPrice > clearing price.
        bidAmount = FixedPointMathLib.fullMulDivUp(1, maxPrice, FixedPoint96.Q96);
        vm.expectRevert(IContinuousClearingAuction.InvalidBidUnableToClear.selector);
        auction.submitBid{value: bidAmount}(maxPrice, uint128(bidAmount), alice, params.floorPrice, bytes(''));

        // Ensure that the auction can finish and checkpoint exactly at the max bid price
        vm.roll(auction.endBlock());
        Checkpoint memory checkpoint = auction.checkpoint();
        assertEq(checkpoint.clearingPrice, maxPrice, 'checkpoint clearing price is not equal to max price');
    }

    function test_WhenCalculatedBidMaxPriceWouldCauseTotalSupplyTimesMaxPriceTimesMPSToOverflow(FuzzDeploymentParams memory _deploymentParams)
        public
        givenFullyFundedAccount
    {
        _deploymentParams.totalSupply = type(uint128).max - 1;
        vm.assume(_deploymentParams.auctionParams.floorPrice > 2);
        _deploymentParams.auctionParams.tickSpacing = 2;
        _deploymentParams.numberOfSteps = 2;
        setUpAuction(_deploymentParams);

        uint256 expectedMaxBidPrice = type(uint256).max / auction.totalSupply();

        uint256 maxPrice = auction.MAX_BID_PRICE();
        assertEq(maxPrice, expectedMaxBidPrice, 'maxPrice is not equal to expectedMaxBidPrice');
        maxPrice = helper__roundPriceDownToTickSpacing(maxPrice, params.tickSpacing);
        // Assert that we didn't fall below after rounding down to tick spacing
        assertEq(
            maxPrice,
            auction.MAX_BID_PRICE(),
            'maxPrice is not equal to MAX_BID_PRICE after rounding down to tick spacing'
        );

        // Assert that the auction was setup correctly
        assertTrue(auction.startBlock() + 2 == auction.endBlock(), 'start block + 1 should be equal to end block');

        vm.roll(auction.startBlock());
        // Since we can't bid more than uint128 in a single bid,
        // we need to submit many bids to raise the price up to the max price.
        uint256 maxBidCurrencyAmount = type(uint128).max;
        uint256 maxBidTokenAmount = maxBidCurrencyAmount * FixedPoint96.Q96 / maxPrice;
        // Factor in the MPS term here
        uint256 numBidsRequired = totalSupply / (maxBidTokenAmount * ConstantsLib.MPS);
        // Show that we need a lot of bids to raise the price to the max price
        assertEq(numBidsRequired, 429, 'numBidsRequired is not 429');

        // We can only submit 429 bids of uint128.max in to the auction until the
        // sumDemandAboveClearingQ96 becomes too large.
        // Observe that this is the same number as the test above
        for (uint256 i = 0; i < 429; i++) {
            auction.submitBid{value: maxBidCurrencyAmount}(
                maxPrice, uint128(maxBidCurrencyAmount), alice, params.floorPrice, bytes('')
            );
        }

        // Show that another bid would revert and be blocked
        vm.expectRevert(IContinuousClearingAuction.InvalidBidUnableToClear.selector);
        auction.submitBid{value: maxBidCurrencyAmount}(
            maxPrice, uint128(maxBidCurrencyAmount), alice, params.floorPrice, bytes('')
        );

        // Show that checkpointing again does not clear the sumDemandAboveClearingQ96,
        // since the price has not moved to the next tick
        vm.roll(block.number + 1);
        auction.checkpoint();

        // And that it is still not possible to submit another bid
        vm.expectRevert(IContinuousClearingAuction.InvalidBidUnableToClear.selector);
        auction.submitBid{value: maxBidCurrencyAmount}(
            maxPrice, uint128(maxBidCurrencyAmount), alice, params.floorPrice, bytes('')
        );

        // Thus, there is no way to submit more than 429 bids into the auction which would
        // cause the operation TOTAL_SUPPLY * MAX_PRICE * MPS to overflow a uint256.
    }

    function test_submitBid_revertsWithBidOwnerCannotBeZeroAddress(FuzzDeploymentParams memory _deploymentParams)
        public
        setUpAuctionFuzz(_deploymentParams)
        givenAuctionHasStarted
        givenFullyFundedAccount
    {
        vm.expectRevert(IContinuousClearingAuction.BidOwnerCannotBeZeroAddress.selector);
        auction.submitBid{value: 1}(1, 1, address(0), params.floorPrice, bytes(''));
    }
}
