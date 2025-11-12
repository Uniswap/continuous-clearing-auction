// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IContinuousClearingAuction} from '../src/interfaces/IContinuousClearingAuction.sol';
import {AuctionParameters} from '../src/interfaces/IContinuousClearingAuction.sol';
import {Bid, BidLib} from '../src/libraries/BidLib.sol';
import {Checkpoint} from '../src/libraries/CheckpointLib.sol';
import {ConstantsLib} from '../src/libraries/ConstantsLib.sol';
import {FixedPoint96} from '../src/libraries/FixedPoint96.sol';
import {MaxBidPriceLib} from '../src/libraries/MaxBidPriceLib.sol';
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
            (bool bidPlaced,) = helper__trySubmitBid(expectedBidId, _bids[i], alice);
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
        vm.expectRevert(
            abi.encodeWithSelector(
                IContinuousClearingAuction.InvalidBidPriceTooHigh.selector, _maxPrice, auction.MAX_BID_PRICE()
            )
        );
        auction.submitBid{value: 1}(_maxPrice, 1, alice, params.floorPrice, bytes(''));
    }

    // Rationale:
    // This test is to verify that the auction will prevent itself from getting into a state where
    // the unchecked math in Auction.sol:_sellTokensAtClearingPrice 202-203 below
    //          unchecked {
    //              totalCurrencyForDeltaQ96X7 = (uint256(TOTAL_SUPPLY) * priceQ96) * deltaMpsU;
    //          }
    // would cause an overflow.
    // To try to hit this case, we create an auction with a very small total supply and submit bids at the
    // maximum allowable price.
    function test_WhenBidMaxPriceWouldCauseTotalSupplyTimesMaxPriceTimesMPSToOverflow(FuzzDeploymentParams memory _deploymentParams)
        public
        givenFullyFundedAccount
    {
        // TOTAL_SUPPLY * MAX_BID_PRICE * MPS does not overflow a uint256

        _deploymentParams.totalSupply = 1;
        uint256 maxBidPrice = MaxBidPriceLib.maxBidPrice(_deploymentParams.totalSupply);

        // Show that TOTAL_SUPPLY * MAX_BID_PRICE * MPS does not overflow a uint256
        uint256 totalSupplyTimesMaxBidPriceTimesMPS = _deploymentParams.totalSupply * maxBidPrice * ConstantsLib.MPS;
        assertLt(
            totalSupplyTimesMaxBidPriceTimesMPS, type(uint256).max, 'totalSupplyTimesMaxBidPriceTimesMPS would overflow'
        );
    }

    // This test is to verify that the auction will prevent itself from getting into a state where
    // the unchecked math in Auction.sol:_sellTokensAtClearingPrice 202-203 would cause an overflow.
    // To try to hit this case, we create an auction with a total supply of MAX_TOTAL_SUPPLY.
    function test_WhenTotalSupplyIsMaxTotalSupply(FuzzDeploymentParams memory _deploymentParams)
        public
        givenFullyFundedAccount
    {
        // TOTAL_SUPPLY * MAX_BID_PRICE * MPS does not overflow a uint256

        _deploymentParams.totalSupply = ConstantsLib.MAX_TOTAL_SUPPLY;
        uint256 maxBidPrice = MaxBidPriceLib.maxBidPrice(_deploymentParams.totalSupply);

        // Show that TOTAL_SUPPLY * MAX_BID_PRICE * MPS does not overflow a uint256
        uint256 totalSupplyTimesMaxBidPriceTimesMPS = _deploymentParams.totalSupply * maxBidPrice * ConstantsLib.MPS;
        assertLt(
            totalSupplyTimesMaxBidPriceTimesMPS, type(uint256).max, 'totalSupplyTimesMaxBidPriceTimesMPS would overflow'
        );
    }

    function test_submitBid_revertsWithBidAmountTooSmall(FuzzDeploymentParams memory _deploymentParams)
        public
        setUpAuctionFuzz(_deploymentParams)
        givenAuctionHasStarted
        givenFullyFundedAccount
    {
        vm.expectRevert(IContinuousClearingAuction.BidAmountTooSmall.selector);
        auction.submitBid{value: 0}(
            1,
            0,
            /* zero amount */
            alice,
            params.floorPrice,
            bytes('')
        );
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
