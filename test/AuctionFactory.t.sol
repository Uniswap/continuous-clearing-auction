// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {AuctionParameters, ContinuousClearingAuction} from '../src/ContinuousClearingAuction.sol';
import {ContinuousClearingAuctionFactory} from '../src/ContinuousClearingAuctionFactory.sol';
import {IContinuousClearingAuction} from '../src/interfaces/IContinuousClearingAuction.sol';
import {IContinuousClearingAuctionFactory} from '../src/interfaces/IContinuousClearingAuctionFactory.sol';
import {ITickStorage} from '../src/interfaces/ITickStorage.sol';
import {ITokenCurrencyStorage} from '../src/interfaces/ITokenCurrencyStorage.sol';
import {IDistributionContract} from '../src/interfaces/external/IDistributionContract.sol';
import {IDistributionStrategy} from '../src/interfaces/external/IDistributionStrategy.sol';
import {FixedPoint96} from '../src/libraries/FixedPoint96.sol';
import {ValueX7Lib} from '../src/libraries/ValueX7Lib.sol';
import {AuctionBaseTest} from './utils/AuctionBaseTest.sol';
import {AuctionParamsBuilder} from './utils/AuctionParamsBuilder.sol';
import {AuctionStepsBuilder} from './utils/AuctionStepsBuilder.sol';
import {FuzzDeploymentParams} from './utils/FuzzStructs.sol';

contract AuctionFactoryTest is AuctionBaseTest {
    using AuctionParamsBuilder for AuctionParameters;
    using AuctionStepsBuilder for bytes;
    using ValueX7Lib for *;

    ContinuousClearingAuctionFactory factory;

    function setUp() public {
        // Setup non fuzz auction
        setUpAuction();
        factory = new ContinuousClearingAuctionFactory();
    }

    function test_initializeDistribution_createsAuction() public {
        bytes memory configData = abi.encode(params);

        // Expect the AuctionCreated event (don't check the auction address since it's deterministic)
        vm.expectEmit(false, true, true, true);
        emit IContinuousClearingAuctionFactory.AuctionCreated(address(0), address(token), TOTAL_SUPPLY, configData);

        IDistributionContract distributionContract =
            factory.initializeDistribution(address(token), TOTAL_SUPPLY, configData, bytes32(0));

        // Verify the auction was created correctly
        ContinuousClearingAuction _auction = ContinuousClearingAuction(payable(address(distributionContract)));
        assertEq(address(_auction.token()), address(token));
        assertEq(_auction.totalSupply(), TOTAL_SUPPLY);
        assertEq(_auction.floorPrice(), FLOOR_PRICE);
        assertEq(_auction.tickSpacing(), TICK_SPACING);
        assertEq(_auction.tokensRecipient(), tokensRecipient);
        assertEq(_auction.fundsRecipient(), fundsRecipient);
        assertEq(_auction.startBlock(), block.number);
        assertEq(_auction.endBlock(), block.number + AUCTION_DURATION);
        assertEq(_auction.claimBlock(), block.number + AUCTION_DURATION + CLAIM_BLOCK_OFFSET);
    }

    function test_initializeDistribution_revertsWithInvalidClaimBlock() public {
        uint256 endBlock = block.number + AUCTION_DURATION;
        bytes memory configData = abi.encode(params.withClaimBlock(endBlock - 1));
        vm.expectRevert(IContinuousClearingAuction.ClaimBlockIsBeforeEndBlock.selector);
        factory.initializeDistribution(address(token), TOTAL_SUPPLY, configData, bytes32(0));
    }

    function test_initializeDistribution_createsAuction_withMsgSenderAsFundsRecipient() public {
        params = params.withFundsRecipient(address(1));
        bytes memory configData = abi.encode(params);

        address sender = makeAddr('sender');
        bytes memory expectedConfigData = abi.encode(params.withFundsRecipient(address(sender)));

        // Expect the AuctionCreated event (don't check the auction address since it's deterministic)
        vm.expectEmit(false, true, true, true);
        emit IContinuousClearingAuctionFactory.AuctionCreated(
            address(0), address(token), TOTAL_SUPPLY, expectedConfigData
        );

        vm.prank(sender);
        IDistributionContract distributionContract =
            factory.initializeDistribution(address(token), TOTAL_SUPPLY, configData, bytes32(0));

        // Verify the auction was created correctly
        ContinuousClearingAuction _auction = ContinuousClearingAuction(payable(address(distributionContract)));
        assertEq(_auction.fundsRecipient(), address(sender));
    }

    function test_initializeDistribution_createsUniqueAddresses() public {
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
        AuctionParameters memory params1 = params.withFloorPrice(FLOOR_PRICE);

        AuctionParameters memory params2 = params.withFloorPrice(FLOOR_PRICE * 2);

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
        bytes memory configData = abi.encode(params);

        IDistributionStrategy strategy = IDistributionStrategy(address(factory));
        IDistributionContract distributionContract =
            strategy.initializeDistribution(address(token), TOTAL_SUPPLY, configData, bytes32(0));

        // Verify it returns a valid distribution contract
        assertTrue(address(distributionContract) != address(0));
    }

    function test_initializeDistribution_createsValidAuction() public {
        bytes memory configData = abi.encode(params);

        IDistributionContract distributionContract =
            factory.initializeDistribution(address(token), TOTAL_SUPPLY, configData, bytes32(0));

        ContinuousClearingAuction _auction = ContinuousClearingAuction(payable(address(distributionContract)));

        // Test that the auction can receive tokens (implements IDistributionContract)
        token.mint(address(_auction), TOTAL_SUPPLY);
        _auction.onTokensReceived();

        // Verify the auction has the correct token balance
        assertEq(token.balanceOf(address(_auction)), TOTAL_SUPPLY);
    }

    function testFuzz_getAuctionAddress(FuzzDeploymentParams memory _deploymentParams, bytes32 _salt, address _sender)
        public
    {
        AuctionParameters memory _params = helper__validFuzzDeploymentParams(_deploymentParams);
        bytes memory configData = abi.encode(_params);

        // Predict the auction address
        address auctionAddress =
            factory.getAuctionAddress(address(token), $deploymentParams.totalSupply, configData, _salt, _sender);

        // Create the actual auction
        vm.prank(_sender);
        IDistributionContract distributionContract =
            factory.initializeDistribution(address(token), $deploymentParams.totalSupply, configData, _salt);

        assertEq(auctionAddress, address(distributionContract));
    }

    function test_initializeDistribution_withZeroTotalSupply_reverts() public {
        bytes memory configData = abi.encode(params);

        vm.expectRevert(ITokenCurrencyStorage.TotalSupplyIsZero.selector);
        factory.initializeDistribution(address(token), 0, configData, bytes32(0));
    }

    function test_initializeDistribution_withZeroFloorPrice_reverts() public {
        params = params.withFloorPrice(0);
        bytes memory configData = abi.encode(params);

        vm.expectRevert(ITickStorage.FloorPriceIsZero.selector);
        factory.initializeDistribution(address(token), TOTAL_SUPPLY, configData, bytes32(0));
    }

    function test_initializeDistribution_withTickSpacingTooSmall_fuzz(uint256 _tickSpacing) public {
        _tickSpacing = _bound(_tickSpacing, 0, 1);
        params = params.withTickSpacing(_tickSpacing);
        bytes memory configData = abi.encode(params);

        vm.expectRevert(ITickStorage.TickSpacingTooSmall.selector);
        factory.initializeDistribution(address(token), TOTAL_SUPPLY, configData, bytes32(0));
    }

    function test_initializeDistribution_withTokenIsAddressZero_reverts() public {
        bytes memory configData = abi.encode(params);

        vm.expectRevert(ITokenCurrencyStorage.TokenIsAddressZero.selector);
        factory.initializeDistribution(address(0), TOTAL_SUPPLY, configData, bytes32(0));
    }

    function test_initializeDistribution_withTokenAndCurrencyAreTheSame_reverts() public {
        params = params.withCurrency(address(token));
        bytes memory configData = abi.encode(params);

        vm.expectRevert(ITokenCurrencyStorage.TokenAndCurrencyCannotBeTheSame.selector);
        factory.initializeDistribution(address(token), TOTAL_SUPPLY, configData, bytes32(0));
    }
}
