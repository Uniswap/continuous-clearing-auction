// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Auction, AuctionParameters} from '../src/Auction.sol';
import {AuctionFactory} from '../src/AuctionFactory.sol';

import {IAuctionFactory} from '../src/interfaces/IAuctionFactory.sol';

import {ITickStorage} from '../src/interfaces/ITickStorage.sol';
import {ITokenCurrencyStorage} from '../src/interfaces/ITokenCurrencyStorage.sol';
import {IDistributionContract} from '../src/interfaces/external/IDistributionContract.sol';
import {IDistributionStrategy} from '../src/interfaces/external/IDistributionStrategy.sol';
import {AuctionStepLib} from '../src/libraries/AuctionStepLib.sol';
import {MPSLib} from '../src/libraries/MPSLib.sol';

import {SupplyLib} from '../src/libraries/SupplyLib.sol';
import {ValueX7, ValueX7Lib} from '../src/libraries/ValueX7Lib.sol';
import {ValueX7X7, ValueX7X7Lib} from '../src/libraries/ValueX7X7Lib.sol';

import {Assertions} from './utils/Assertions.sol';
import {AuctionParamsBuilder} from './utils/AuctionParamsBuilder.sol';
import {AuctionStepsBuilder} from './utils/AuctionStepsBuilder.sol';
import {TokenHandler} from './utils/TokenHandler.sol';
import {Test} from 'forge-std/Test.sol';

contract AuctionFactoryTest is TokenHandler, Test, Assertions {
    using AuctionParamsBuilder for AuctionParameters;
    using AuctionStepsBuilder for bytes;
    using ValueX7Lib for *;
    using ValueX7X7Lib for *;

    AuctionFactory factory;
    Auction auction;

    uint256 public constant AUCTION_DURATION = 100;
    uint256 public constant TICK_SPACING = 1e6;
    uint256 public constant FLOOR_PRICE = 1e6;
    uint256 public constant TOTAL_SUPPLY = 1000e18;

    address public alice;
    address public tokensRecipient;
    address public fundsRecipient;

    AuctionParameters public params;
    bytes public auctionStepsData;

    function setUp() public {
        setUpTokens();

        alice = makeAddr('alice');
        tokensRecipient = makeAddr('tokensRecipient');
        fundsRecipient = makeAddr('fundsRecipient');

        // Setup base params
        auctionStepsData = AuctionStepsBuilder.init().addStep(100e3, 100);
        params = AuctionParamsBuilder.init().withCurrency(ETH_SENTINEL).withFloorPrice(FLOOR_PRICE).withTickSpacing(
            TICK_SPACING
        ).withValidationHook(address(0)).withTokensRecipient(tokensRecipient).withFundsRecipient(fundsRecipient)
            .withStartBlock(block.number).withEndBlock(block.number + AUCTION_DURATION).withClaimBlock(
            block.number + AUCTION_DURATION
        ).withAuctionStepsData(auctionStepsData);

        factory = new AuctionFactory();
    }

    function test_initializeDistribution_createsAuction() public {
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

    function test_initializeDistribution_createsAuction_withMsgSenderAsFundsRecipient() public {
        params = params.withFundsRecipient(address(1));
        bytes memory configData = abi.encode(params);

        address sender = makeAddr('sender');
        bytes memory expectedConfigData = abi.encode(params.withFundsRecipient(address(sender)));

        // Expect the AuctionCreated event (don't check the auction address since it's deterministic)
        vm.expectEmit(false, true, true, true);
        emit IAuctionFactory.AuctionCreated(address(0), address(token), TOTAL_SUPPLY, expectedConfigData);

        vm.prank(sender);
        IDistributionContract distributionContract =
            factory.initializeDistribution(address(token), TOTAL_SUPPLY, configData, bytes32(0));

        // Verify the auction was created correctly
        auction = Auction(payable(address(distributionContract)));
        assertEq(auction.fundsRecipient(), address(sender));
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

        auction = Auction(payable(address(distributionContract)));

        // Test that the auction can receive tokens (implements IDistributionContract)
        token.mint(address(auction), TOTAL_SUPPLY);
        auction.onTokensReceived();

        // Verify the auction has the correct token balance
        assertEq(token.balanceOf(address(auction)), TOTAL_SUPPLY);
    }

    function helper__assumeValidDeploymentParams(
        address _token,
        uint256 _totalSupply,
        bytes32 _salt,
        AuctionParameters memory _params,
        uint8 _numberOfSteps
    ) public pure returns (uint256 totalSupply) {
        _totalSupply = bound(_totalSupply, 1, SupplyLib.MAX_TOTAL_SUPPLY);
        vm.assume(_token != address(0));

        vm.assume(_params.currency != address(0));
        vm.assume(_params.tokensRecipient != address(0));
        vm.assume(_params.fundsRecipient != address(0));
        vm.assume(_params.startBlock != 0);
        vm.assume(_params.claimBlock != 0);

        // -2 because we need to account for the endBlock and claimBlock
        vm.assume(_params.startBlock <= type(uint64).max - _numberOfSteps - 2);
        _params.endBlock = _params.startBlock + uint64(_numberOfSteps);
        _params.claimBlock = _params.endBlock + 1;

        vm.assume(_params.graduationThresholdMps != 0);
        vm.assume(_params.validationHook != address(0));
        vm.assume(_params.tickSpacing != 0);
        vm.assume(_params.floorPrice != 0 && _params.floorPrice % _params.tickSpacing == 0);
        vm.assume(_salt != bytes32(0));

        vm.assume(_numberOfSteps > 0);
        vm.assume(MPSLib.MPS % _numberOfSteps == 0); // such that it is divisible

        // Replace auction steps data with a valid one
        // Divide steps by number of bips
        uint256 _numberOfMps = MPSLib.MPS / _numberOfSteps;
        bytes memory _auctionStepsData = new bytes(0);
        for (uint8 i = 0; i < _numberOfSteps; i++) {
            _auctionStepsData = AuctionStepsBuilder.addStep(_auctionStepsData, uint24(_numberOfMps), uint40(1));
        }
        _params.auctionStepsData = _auctionStepsData;
        vm.assume(_params.claimBlock > _params.endBlock);

        // Bound graduation threshold mps
        _params.graduationThresholdMps = uint24(bound(_params.graduationThresholdMps, 0, uint24(MPSLib.MPS)));

        return _totalSupply;
    }

    function testFuzz_getAuctionAddress(
        address _token,
        uint256 _totalSupply,
        bytes32 _salt,
        uint8 _numberOfSteps,
        AuctionParameters memory _params
    ) public {
        _totalSupply = helper__assumeValidDeploymentParams(_token, _totalSupply, _salt, _params, _numberOfSteps);

        bytes memory configData = abi.encode(_params);

        // Predict the auction address
        address auctionAddress = factory.getAuctionAddress(_token, _totalSupply, configData, _salt);

        // Create the actual auction
        IDistributionContract distributionContract =
            factory.initializeDistribution(_token, _totalSupply, configData, _salt);

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

    function test_initializeDistribution_withZeroTickSpacing_reverts() public {
        params = params.withTickSpacing(0);
        bytes memory configData = abi.encode(params);

        vm.expectRevert(ITickStorage.TickSpacingIsZero.selector);
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
