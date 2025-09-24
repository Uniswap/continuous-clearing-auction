// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Auction} from 'src/Auction.sol';
import {Tick} from 'src/TickStorage.sol';
import {AuctionParameters, IAuction} from 'src/interfaces/IAuction.sol';
import {ITickStorage} from 'src/interfaces/ITickStorage.sol';
import {Demand} from 'src/libraries/DemandLib.sol';
import {FixedPoint96} from 'src/libraries/FixedPoint96.sol';
import {AuctionParamsBuilder} from './AuctionParamsBuilder.sol';
import {AuctionStepsBuilder} from './AuctionStepsBuilder.sol';

import {MockFundsRecipient} from './MockFundsRecipient.sol';
import {TokenHandler} from './TokenHandler.sol';
import {Test} from 'forge-std/Test.sol';

import {MPSLib} from 'src/libraries/MPSLib.sol';

/// @notice Handler contract for setting up an auction
abstract contract AuctionBaseTest is TokenHandler, Test {
    using AuctionParamsBuilder for AuctionParameters;
    using AuctionStepsBuilder for bytes;

    Auction public auction;

    uint256 public constant AUCTION_DURATION = 100;
    uint256 public constant TICK_SPACING = 100;
    uint256 public constant FLOOR_PRICE = 1000 << FixedPoint96.RESOLUTION;
    uint256 public constant TOTAL_SUPPLY = 1000e18;

    address public alice;
    address public tokensRecipient;
    address public fundsRecipient;
    MockFundsRecipient public mockFundsRecipient;

    AuctionParameters public params;
    bytes public auctionStepsData;

    struct FuzzDeploymentParams {
        uint256 totalSupply;
        AuctionParameters auctionParams;
        uint8 numberOfSteps;
    }

    function helper__validFuzzDeploymentParams(
        FuzzDeploymentParams memory _deploymentParams
    ) public returns (AuctionParameters memory) {
        // Hard coded for tests
        _deploymentParams.auctionParams.currency = ETH_SENTINEL;
        _deploymentParams.auctionParams.tokensRecipient = tokensRecipient;
        _deploymentParams.auctionParams.fundsRecipient = fundsRecipient;
        _deploymentParams.auctionParams.validationHook = address(0);

        // vm.assume(_deploymentParams.totalSupply <= type(uint224).max / (MPSLib.MPS ** 2));

        // TODO: constantify
        uint256 X7_UPPER_BOUND = (type(uint256).max) / 1e14;
        _deploymentParams.totalSupply = bound(_deploymentParams.totalSupply, 1, X7_UPPER_BOUND);


        // -2 because we need to account for the endBlock and claimBlock
        _deploymentParams.auctionParams.startBlock = uint64(bound(_deploymentParams.auctionParams.startBlock, block.number, type(uint64).max - _deploymentParams.numberOfSteps - 2));
        _deploymentParams.auctionParams.endBlock = _deploymentParams.auctionParams.startBlock + uint64(_deploymentParams.numberOfSteps);
        _deploymentParams.auctionParams.claimBlock = _deploymentParams.auctionParams.endBlock + 1;

        vm.assume(_deploymentParams.auctionParams.graduationThresholdMps != 0);
        
        // Dont have tick spacing or floor price too large
        _deploymentParams.auctionParams.floorPrice = bound(_deploymentParams.auctionParams.floorPrice, 0, type(uint128).max);
        _deploymentParams.auctionParams.tickSpacing = bound(_deploymentParams.auctionParams.tickSpacing, 0, type(uint128).max);

        vm.assume(_deploymentParams.auctionParams.tickSpacing != 0);
        vm.assume(_deploymentParams.auctionParams.floorPrice != 0);

        vm.assume(_deploymentParams.numberOfSteps > 0);
        vm.assume(MPSLib.MPS % _deploymentParams.numberOfSteps == 0); // such that it is divisible

        // TODO(md): fix and have variation in the step sizes

        // Replace auction steps data with a valid one
        // Divide steps by number of bips
        uint256 _numberOfMps = MPSLib.MPS / _deploymentParams.numberOfSteps;
        bytes memory _auctionStepsData = new bytes(0);
        for (uint8 i = 0; i < _deploymentParams.numberOfSteps; i++) {
            _auctionStepsData = AuctionStepsBuilder.addStep(_auctionStepsData, uint24(_numberOfMps), uint40(1));
        }
        _deploymentParams.auctionParams.auctionStepsData = _auctionStepsData;

        // Bound graduation threshold mps
        _deploymentParams.auctionParams.graduationThresholdMps = uint24(bound(_deploymentParams.auctionParams.graduationThresholdMps, 0, uint24(MPSLib.MPS)));

        return _deploymentParams.auctionParams;
    }

    // Fuzzing variant of setUpAuction
    function setUpAuction(FuzzDeploymentParams memory _deploymentParams) public {
        setUpTokens();

        alice = makeAddr('alice');
        tokensRecipient = makeAddr('tokensRecipient');
        fundsRecipient = makeAddr('fundsRecipient');
        mockFundsRecipient = new MockFundsRecipient();

        params = helper__validFuzzDeploymentParams(_deploymentParams);

        // Expect the floor price tick to be initialized
        // TODO(md): fix
        // vm.expectEmit(true, true, true, true);
        // emit ITickStorage.TickInitialized(tickNumberToPriceX96(1));
        auction = new Auction(address(token), _deploymentParams.totalSupply, params);

        token.mint(address(auction), _deploymentParams.totalSupply);
    }

    // Non fuzzing variant of setUpAuction
    function setUpAuction() public {
        setUpTokens();

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
        auction = new Auction(address(token), TOTAL_SUPPLY, params);

        token.mint(address(auction), TOTAL_SUPPLY);
    }



    /// @dev Helper function to convert a tick number to a priceX96
    function tickNumberToPriceX96(uint256 tickNumber) internal pure returns (uint256) {
        return ((FLOOR_PRICE >> FixedPoint96.RESOLUTION) + (tickNumber - 1) * TICK_SPACING) << FixedPoint96.RESOLUTION;
    }

    /// @notice Helper function to return the tick at the given price
    function getTick(uint256 price) public view returns (Tick memory) {
        (uint256 next, Demand memory demand) = auction.ticks(price);
        return Tick({next: next, demand: demand});
    }
}
