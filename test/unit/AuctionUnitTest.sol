// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ContinuousClearingAuction} from '../../src/ContinuousClearingAuction.sol';
import {AuctionParameters} from '../../src/interfaces/IContinuousClearingAuction.sol';
import {ITickStorage} from '../../src/interfaces/ITickStorage.sol';
import {Bid, BidLib} from '../../src/libraries/BidLib.sol';
import {Checkpoint} from '../../src/libraries/CheckpointLib.sol';
import {ValueX7} from '../../src/libraries/ValueX7Lib.sol';
import {AuctionBaseTest} from '../utils/AuctionBaseTest.sol';
import {AuctionParamsBuilder} from '../utils/AuctionParamsBuilder.sol';
import {AuctionStepsBuilder} from '../utils/AuctionStepsBuilder.sol';
import {FuzzDeploymentParams} from '../utils/FuzzStructs.sol';
import {MockContinuousClearingAuction} from '../utils/MockAuction.sol';

contract AuctionUnitTest is AuctionBaseTest {
    using AuctionParamsBuilder for AuctionParameters;
    using AuctionStepsBuilder for bytes;

    MockContinuousClearingAuction public mockAuction;

    /// @dev Sets up the auction for fuzzing, ensuring valid parameters
    modifier setUpMockAuctionFuzz(FuzzDeploymentParams memory _deploymentParams) {
        setUpMockAuction(_deploymentParams);
        _;
    }

    function setUpMockAuction(FuzzDeploymentParams memory _deploymentParams) public {
        setUpTokens();

        alice = makeAddr('alice');
        tokensRecipient = makeAddr('tokensRecipient');
        fundsRecipient = makeAddr('fundsRecipient');

        params = helper__validFuzzDeploymentParams(_deploymentParams);
        // Expect the floor price tick to be initialized
        vm.expectEmit(true, true, true, true);
        emit ITickStorage.TickInitialized(_deploymentParams.auctionParams.floorPrice);
        mockAuction = new MockContinuousClearingAuction(address(token), _deploymentParams.totalSupply, params);

        token.mint(address(mockAuction), _deploymentParams.totalSupply);
        mockAuction.onTokensReceived();
    }

    function setUpMockAuctionInvariant() public {
        setUpMockAuction();

        FuzzDeploymentParams memory fuzzDeploymentParams = helper__validInvariantDeploymentParams();

        // Expect the floor price tick to be initialized
        vm.expectEmit(true, true, true, true);
        emit ITickStorage.TickInitialized(fuzzDeploymentParams.auctionParams.floorPrice);
        mockAuction = new MockContinuousClearingAuction(
            address(token), fuzzDeploymentParams.totalSupply, fuzzDeploymentParams.auctionParams
        );

        token.mint(address(mockAuction), fuzzDeploymentParams.totalSupply);
        mockAuction.onTokensReceived();
    }

    // Non fuzzing variant of setUpMockAuction
    function setUpMockAuction() public requireAuctionNotSetup {
        setUpTokens();

        alice = makeAddr('alice');
        tokensRecipient = makeAddr('tokensRecipient');
        fundsRecipient = makeAddr('fundsRecipient');

        auctionStepsData =
            AuctionStepsBuilder.init().addStep(STANDARD_MPS_1_PERCENT, 50).addStep(STANDARD_MPS_1_PERCENT, 50);
        params = AuctionParamsBuilder.init().withCurrency(ETH_SENTINEL).withFloorPrice(FLOOR_PRICE)
            .withTickSpacing(TICK_SPACING).withValidationHook(address(0)).withTokensRecipient(tokensRecipient)
            .withFundsRecipient(fundsRecipient).withStartBlock(block.number)
            .withEndBlock(block.number + AUCTION_DURATION).withClaimBlock(block.number + AUCTION_DURATION + 10)
            .withAuctionStepsData(auctionStepsData);

        // Expect the floor price tick to be initialized
        vm.expectEmit(true, true, true, true);
        emit ITickStorage.TickInitialized(tickNumberToPriceX96(1));
        mockAuction = new MockContinuousClearingAuction(address(token), TOTAL_SUPPLY, params);

        token.mint(address(mockAuction), TOTAL_SUPPLY);
        // Expect the tokens to be received
        mockAuction.onTokensReceived();
    }
}
