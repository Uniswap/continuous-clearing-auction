// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from 'forge-std/Test.sol';
import {FixedPointMathLib} from 'solady/utils/FixedPointMathLib.sol';
import {ContinuousClearingAuction} from 'src/ContinuousClearingAuction.sol';
import {ITickStorage} from 'src/interfaces/ITickStorage.sol';
import {FixedPoint96} from 'src/libraries/FixedPoint96.sol';
import {AuctionBaseTest} from 'test/utils/AuctionBaseTest.sol';
import {AuctionStepsBuilder} from 'test/utils/AuctionStepsBuilder.sol';
import {FuzzDeploymentParams} from 'test/utils/FuzzStructs.sol';

/// @title AuctionDosTest
/// @notice Test showing that `forceIterateOverTicks` can unbrick the auction in a DoS attack
contract AuctionDosTest is AuctionBaseTest {
    using AuctionStepsBuilder for bytes;

    uint256 public constant FUSAKA_TX_GAS_LIMIT = 16_000_000;
    uint256 public constant DOS_BIDS_COUNT = 5000; // At 5k gas / tick this exceeds 16M
    uint256 public constant MAX_ITERABLE_TICKS = 3000; // Nets out to 15M gas, under the FUSAKA_TX_GAS_LIMIT

    // This test is quite slow so only fuzz 100 times. We hardcode most of the params for simplicity anyways
    /// forge-config: default.isolate = true
    /// forge-config: default.gas_limit = 9223372036854775807
    /// forge-config: ci.isolate = true
    /// forge-config: ci.gas_limit = 9223372036854775807
    /// forge-config: default.fuzz.runs = 100
    /// forge-config: ci.fuzz.runs = 100
    function test_forceIterateOverTicks_preventsDoS(FuzzDeploymentParams memory _deploymentParams)
        public
        givenFullyFundedAccount
    {
        setUpTokens();

        alice = makeAddr('alice');
        bob = makeAddr('bob');
        tokensRecipient = makeAddr('tokensRecipient');
        fundsRecipient = makeAddr('fundsRecipient');

        _deploymentParams.auctionParams = helper__validFuzzDeploymentParams(_deploymentParams);
        vm.assume(_deploymentParams.auctionParams.startBlock < type(uint64).max - 1e7);
        // Override certain params
        _deploymentParams.totalSupply = 1000e18;
        _deploymentParams.auctionParams.tickSpacing = 1 << FixedPoint96.RESOLUTION;
        _deploymentParams.auctionParams.floorPrice = 10 << FixedPoint96.RESOLUTION;
        _deploymentParams.auctionParams.endBlock = uint64(_deploymentParams.auctionParams.startBlock + 1e7);
        _deploymentParams.auctionParams.claimBlock = uint64(_deploymentParams.auctionParams.endBlock + 1);
        _deploymentParams.auctionParams.auctionStepsData = AuctionStepsBuilder.init().addStep(1, 1e7);
        _deploymentParams.auctionParams.validationHook = address(0);

        auction = new ContinuousClearingAuction(
            address(token), _deploymentParams.totalSupply, _deploymentParams.auctionParams
        );
        token.mint(address(auction), _deploymentParams.totalSupply);
        auction.onTokensReceived();

        vm.roll(auction.startBlock());

        for (uint256 i = 1; i <= DOS_BIDS_COUNT; i++) {
            auction.submitBid{value: 1}(
                _deploymentParams.auctionParams.floorPrice + i * _deploymentParams.auctionParams.tickSpacing,
                1,
                alice,
                _deploymentParams.auctionParams.floorPrice + (i - 1) * _deploymentParams.auctionParams.tickSpacing,
                bytes('')
            );
        }

        vm.roll(block.number + 1);

        // Now bid a large amount to move the price up to the highest tick
        uint256 maxPrice =
            _deploymentParams.auctionParams.floorPrice + DOS_BIDS_COUNT * _deploymentParams.auctionParams.tickSpacing;
        uint256 prevPrice = _deploymentParams.auctionParams.floorPrice + (DOS_BIDS_COUNT - 1)
            * _deploymentParams.auctionParams.tickSpacing;
        uint128 bidAmount = uint128(FixedPointMathLib.fullMulDivUp(auction.totalSupply(), maxPrice, FixedPoint96.Q96));

        // Move the auction up to the highest tick
        auction.submitBid{value: bidAmount}(maxPrice, bidAmount, alice, prevPrice, bytes(''));

        vm.roll(block.number + 1);
        // This should revert due to OOG
        vm.expectRevert();
        auction.checkpoint{gas: FUSAKA_TX_GAS_LIMIT}();

        uint256 untilTickPrice = _deploymentParams.auctionParams.floorPrice + MAX_ITERABLE_TICKS
            * _deploymentParams.auctionParams.tickSpacing;
        vm.expectEmit(true, true, true, true);
        emit ITickStorage.NextActiveTickUpdated(untilTickPrice);
        auction.forceIterateOverTicks{gas: FUSAKA_TX_GAS_LIMIT}(untilTickPrice);

        emit log_named_uint('gasleft', gasleft());
        require(gasleft() > FUSAKA_TX_GAS_LIMIT, 'Gas left is not greater than FUSAKA_TX_GAS_LIMIT');

        // Now you should be able to checkpoint
        auction.checkpoint{gas: FUSAKA_TX_GAS_LIMIT}();
    }
}
