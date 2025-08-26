// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Auction, AuctionParameters} from '../src/Auction.sol';
import {AuctionFactory} from '../src/AuctionFactory.sol';
import {IAuctionFactory} from '../src/interfaces/IAuctionFactory.sol';
import {IDistributionContract} from '../src/interfaces/external/IDistributionContract.sol';
import {IDistributionStrategy} from '../src/interfaces/external/IDistributionStrategy.sol';
import {AuctionParamsBuilder} from './utils/AuctionParamsBuilder.sol';
import {AuctionStepsBuilder} from './utils/AuctionStepsBuilder.sol';
import {TokenHandler} from './utils/TokenHandler.sol';
import {Test} from 'forge-std/Test.sol';

contract AuctionFactoryTest is TokenHandler, Test {
    using AuctionParamsBuilder for AuctionParameters;
    using AuctionStepsBuilder for bytes;

    AuctionFactory factory;
    Auction auction;

    uint256 public constant AUCTION_DURATION = 100;
    uint256 public constant TICK_SPACING = 1e6;
    uint128 public constant FLOOR_PRICE = 1e6;
    uint256 public constant TOTAL_SUPPLY = 1000e18;

    address public alice;
    address public tokensRecipient;
    address public fundsRecipient;

    function setUp() public {
        setUpTokens();

        alice = makeAddr('alice');
        tokensRecipient = makeAddr('tokensRecipient');
        fundsRecipient = makeAddr('fundsRecipient');

        factory = new AuctionFactory();
    }

    function test_initializeDistribution_createsAuction() public {
        bytes memory auctionStepsData = AuctionStepsBuilder.init().addStep(100e3, 100);
        AuctionParameters memory params = AuctionParamsBuilder.init().withCurrency(ETH_SENTINEL).withFloorPrice(
            FLOOR_PRICE
        ).withTickSpacing(TICK_SPACING).withValidationHook(address(0)).withTokensRecipient(tokensRecipient)
            .withFundsRecipient(fundsRecipient).withStartBlock(block.number).withEndBlock(block.number + AUCTION_DURATION)
            .withClaimBlock(block.number + AUCTION_DURATION).withAuctionStepsData(auctionStepsData);

        bytes memory configData = abi.encode(params);

        // Expect the AuctionCreated event (don't check the auction address since it's deterministic)
        vm.expectEmit(false, true, true, true);
        emit IAuctionFactory.AuctionCreated(address(0), address(token), TOTAL_SUPPLY, configData);

        IDistributionContract distributionContract =
            factory.initializeDistribution(address(token), TOTAL_SUPPLY, configData, bytes32(0));

        // Verify the auction was created correctly
        auction = Auction(payable(address(distributionContract)));
        assertEq(address(auction.token()), address(token));
        assertEq(auction.totalSupply(), TOTAL_SUPPLY);
        assertEq(auction.floorPrice(), FLOOR_PRICE);
        assertEq(auction.tickSpacing(), TICK_SPACING);
        assertEq(auction.tokensRecipient(), tokensRecipient);
        assertEq(auction.fundsRecipient(), fundsRecipient);
        assertEq(auction.startBlock(), block.number);
        assertEq(auction.endBlock(), block.number + AUCTION_DURATION);
        assertEq(auction.claimBlock(), block.number + AUCTION_DURATION);
    }

    function test_initializeDistribution_createsUniqueAddresses() public {
        bytes memory auctionStepsData = AuctionStepsBuilder.init().addStep(100e3, 100);
        AuctionParameters memory params = AuctionParamsBuilder.init().withCurrency(ETH_SENTINEL).withFloorPrice(
            FLOOR_PRICE
        ).withTickSpacing(TICK_SPACING).withValidationHook(address(0)).withTokensRecipient(tokensRecipient)
            .withFundsRecipient(fundsRecipient).withStartBlock(block.number).withEndBlock(block.number + AUCTION_DURATION)
            .withClaimBlock(block.number + AUCTION_DURATION).withAuctionStepsData(auctionStepsData);

        bytes memory configData = abi.encode(params);

        // Create first auction
        IDistributionContract distributionContract1 =
            factory.initializeDistribution(address(token), TOTAL_SUPPLY, configData, bytes32(0));

        // Create second auction with different amount
        IDistributionContract distributionContract2 =
            factory.initializeDistribution(address(token), TOTAL_SUPPLY * 2, configData, bytes32(0));

        // Addresses should be different due to different amount in salt
        assertTrue(address(distributionContract1) != address(distributionContract2));
    }

    function test_initializeDistribution_withDifferentTokens() public {
        bytes memory auctionStepsData = AuctionStepsBuilder.init().addStep(100e3, 100);
        AuctionParameters memory params = AuctionParamsBuilder.init().withCurrency(ETH_SENTINEL).withFloorPrice(
            FLOOR_PRICE
        ).withTickSpacing(TICK_SPACING).withValidationHook(address(0)).withTokensRecipient(tokensRecipient)
            .withFundsRecipient(fundsRecipient).withStartBlock(block.number).withEndBlock(block.number + AUCTION_DURATION)
            .withClaimBlock(block.number + AUCTION_DURATION).withAuctionStepsData(auctionStepsData);

        bytes memory configData = abi.encode(params);

        // Create auction with token1
        IDistributionContract distributionContract1 =
            factory.initializeDistribution(address(token), TOTAL_SUPPLY, configData, bytes32(0));

        // Create auction with token2 (different token address)
        address token2 = makeAddr('token2');
        IDistributionContract distributionContract2 =
            factory.initializeDistribution(token2, TOTAL_SUPPLY, configData, bytes32(0));

        // Addresses should be different due to different token in salt
        assertTrue(address(distributionContract1) != address(distributionContract2));
    }

    function test_initializeDistribution_withDifferentAmounts() public {
        bytes memory auctionStepsData = AuctionStepsBuilder.init().addStep(100e3, 100);
        AuctionParameters memory params = AuctionParamsBuilder.init().withCurrency(ETH_SENTINEL).withFloorPrice(
            FLOOR_PRICE
        ).withTickSpacing(TICK_SPACING).withValidationHook(address(0)).withTokensRecipient(tokensRecipient)
            .withFundsRecipient(fundsRecipient).withStartBlock(block.number).withEndBlock(block.number + AUCTION_DURATION)
            .withClaimBlock(block.number + AUCTION_DURATION).withAuctionStepsData(auctionStepsData);

        bytes memory configData = abi.encode(params);

        // Create auction with amount1
        IDistributionContract distributionContract1 =
            factory.initializeDistribution(address(token), TOTAL_SUPPLY, configData, bytes32(0));

        // Create auction with amount2 (different amount)
        IDistributionContract distributionContract2 =
            factory.initializeDistribution(address(token), TOTAL_SUPPLY * 2, configData, bytes32(0));

        // Addresses should be different due to different amount in salt
        assertTrue(address(distributionContract1) != address(distributionContract2));
    }

    function test_initializeDistribution_withDifferentParameters() public {
        bytes memory auctionStepsData = AuctionStepsBuilder.init().addStep(100e3, 100);
        AuctionParameters memory params1 = AuctionParamsBuilder.init().withCurrency(ETH_SENTINEL).withFloorPrice(
            FLOOR_PRICE
        ).withTickSpacing(TICK_SPACING).withValidationHook(address(0)).withTokensRecipient(tokensRecipient)
            .withFundsRecipient(fundsRecipient).withStartBlock(block.number).withEndBlock(block.number + AUCTION_DURATION)
            .withClaimBlock(block.number + AUCTION_DURATION).withAuctionStepsData(auctionStepsData);

        AuctionParameters memory params2 = AuctionParamsBuilder.init().withCurrency(ETH_SENTINEL).withFloorPrice(
            FLOOR_PRICE * 2
        ).withTickSpacing(TICK_SPACING).withValidationHook(address(0)).withTokensRecipient(tokensRecipient)
            .withFundsRecipient(fundsRecipient).withStartBlock(block.number).withEndBlock(block.number + AUCTION_DURATION)
            .withClaimBlock(block.number + AUCTION_DURATION) // Different floor price
            .withAuctionStepsData(auctionStepsData);

        bytes memory configData1 = abi.encode(params1);
        bytes memory configData2 = abi.encode(params2);

        // Create auction with params1
        IDistributionContract distributionContract1 =
            factory.initializeDistribution(address(token), TOTAL_SUPPLY, configData1, bytes32(0));

        // Create auction with params2
        IDistributionContract distributionContract2 =
            factory.initializeDistribution(address(token), TOTAL_SUPPLY, configData2, bytes32(0));

        // Addresses should be different due to different parameters in salt
        assertTrue(address(distributionContract1) != address(distributionContract2));
    }

    function test_initializeDistribution_implementsIDistributionStrategy() public {
        bytes memory auctionStepsData = AuctionStepsBuilder.init().addStep(100e3, 100);
        AuctionParameters memory params = AuctionParamsBuilder.init().withCurrency(ETH_SENTINEL).withFloorPrice(
            FLOOR_PRICE
        ).withTickSpacing(TICK_SPACING).withValidationHook(address(0)).withTokensRecipient(tokensRecipient)
            .withFundsRecipient(fundsRecipient).withStartBlock(block.number).withEndBlock(block.number + AUCTION_DURATION)
            .withClaimBlock(block.number + AUCTION_DURATION).withAuctionStepsData(auctionStepsData);

        bytes memory configData = abi.encode(params);

        IDistributionStrategy strategy = IDistributionStrategy(address(factory));
        IDistributionContract distributionContract =
            strategy.initializeDistribution(address(token), TOTAL_SUPPLY, configData, bytes32(0));

        // Verify it returns a valid distribution contract
        assertTrue(address(distributionContract) != address(0));
    }

    function test_initializeDistribution_createsValidAuction() public {
        bytes memory auctionStepsData = AuctionStepsBuilder.init().addStep(100e3, 100);
        AuctionParameters memory params = AuctionParamsBuilder.init().withCurrency(ETH_SENTINEL).withFloorPrice(
            FLOOR_PRICE
        ).withTickSpacing(TICK_SPACING).withValidationHook(address(0)).withTokensRecipient(tokensRecipient)
            .withFundsRecipient(fundsRecipient).withStartBlock(block.number).withEndBlock(block.number + AUCTION_DURATION)
            .withClaimBlock(block.number + AUCTION_DURATION).withAuctionStepsData(auctionStepsData);

        bytes memory configData = abi.encode(params);

        IDistributionContract distributionContract =
            factory.initializeDistribution(address(token), TOTAL_SUPPLY, configData, bytes32(0));

        auction = Auction(payable(address(distributionContract)));

        // Test that the auction can receive tokens (implements IDistributionContract)
        token.mint(address(auction), TOTAL_SUPPLY);
        auction.onTokensReceived();

        // Verify the auction has the correct token balance
        assertEq(token.balanceOf(address(auction)), TOTAL_SUPPLY);
    }
}
