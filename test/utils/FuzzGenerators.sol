// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ConstantsLib} from '../../src/libraries/ConstantsLib.sol';
import {FixedPoint96} from '../../src/libraries/FixedPoint96.sol';
import {MaxBidPriceLib} from '../../src/libraries/MaxBidPriceLib.sol';
import {AuctionStepsBuilder} from './AuctionStepsBuilder.sol';
import {FuzzDeploymentParams} from './FuzzStructs.sol';
import {FixedPointMathLib} from 'solady/utils/FixedPointMathLib.sol';
import {SafeCastLib} from 'solady/utils/SafeCastLib.sol';

/// @notice Pure seed-based generators for reusable auction fuzz fixtures.
/// @dev These helpers intentionally avoid test-contract storage and cheatcodes so unit, fuzz,
///      invariant, and combinatorial tests can share the same parameter generation logic.
library FuzzGenerators {
    using FixedPointMathLib for uint256;

    uint256 internal constant BPS = 10_000;

    /// @notice Derive a deterministic uint256 from a seed and domain-specific salt.
    function seededUint256(uint256 seed, string memory salt) internal pure returns (uint256) {
        return uint256(keccak256(abi.encodePacked(seed, salt)));
    }

    /// @notice Pick a valid number of auction steps that evenly divides ConstantsLib.MPS.
    function seededDivisorOfMPS(uint256 seed) internal pure returns (uint8) {
        uint8[20] memory validDivisors = [
            uint8(1),
            uint8(2),
            uint8(4),
            uint8(5),
            uint8(8),
            uint8(10),
            uint8(16),
            uint8(20),
            uint8(25),
            uint8(32),
            uint8(40),
            uint8(50),
            uint8(64),
            uint8(80),
            uint8(100),
            uint8(125),
            uint8(128),
            uint8(160),
            uint8(200),
            uint8(250)
        ];

        return validDivisors[seed % validDivisors.length];
    }

    /// @notice Pick a fixture tick spacing as basis points of floor price.
    /// @dev Buckets are 0.01%, 1%, 10%, 100%, and 1000% of floor price.
    function fixtureTickSpacingBps(uint256 seed) internal pure returns (uint256) {
        uint32[5] memory tickSpacingBps = [uint32(1), uint32(100), uint32(1000), uint32(10_000), uint32(100_000)];
        return tickSpacingBps[seed % tickSpacingBps.length];
    }

    /// @notice Pick a fixture graduation target from common edge cases.
    function fixtureRequiredCurrencyRaised(uint256 seed, uint128 totalSupply, uint256 floorPrice)
        internal
        pure
        returns (uint128)
    {
        uint128 fullyFundedAtFloorPrice =
            SafeCastLib.toUint128(uint256(totalSupply).fullMulDiv(floorPrice, FixedPoint96.Q96));
        uint128[3] memory requiredCurrencyRaisedFixtures = [uint128(0), fullyFundedAtFloorPrice, type(uint128).max];
        return requiredCurrencyRaisedFixtures[seed % requiredCurrencyRaisedFixtures.length];
    }

    /// @notice Build a complete, constructor-valid deployment parameter set from a seed.
    /// @param seed Entropy source used to derive every generated field.
    /// @param currency Auction currency address.
    /// @param tokensRecipient Recipient for unsold tokens.
    /// @param fundsRecipient Recipient for raised currency.
    /// @param validationHook Optional validation hook.
    /// @param currentBlock Minimum start block for the generated auction.
    function seededDeploymentParams(
        uint256 seed,
        address currency,
        address tokensRecipient,
        address fundsRecipient,
        address validationHook,
        uint256 currentBlock
    ) internal pure returns (FuzzDeploymentParams memory deploymentParams) {
        deploymentParams.auctionParams.currency = currency;
        deploymentParams.auctionParams.tokensRecipient = tokensRecipient;
        deploymentParams.auctionParams.fundsRecipient = fundsRecipient;
        deploymentParams.auctionParams.validationHook = validationHook;

        deploymentParams.totalSupply =
            uint128(1 + (seededUint256(seed, 'totalSupply') % uint256(ConstantsLib.MAX_TOTAL_SUPPLY)));
        deploymentParams.numberOfSteps = seededDivisorOfMPS(seededUint256(seed, 'numberOfSteps'));

        uint256 maxBidPrice = MaxBidPriceLib.maxBidPrice(deploymentParams.totalSupply);
        uint256 tickSpacingBps = fixtureTickSpacingBps(seededUint256(seed, 'tickSpacingBps'));
        uint256 maxFloorPrice = tickSpacingBps > BPS
            ? (maxBidPrice * BPS) / (2 * tickSpacingBps)
            : (maxBidPrice * BPS) / (BPS + tickSpacingBps);

        // Select a seeded floor price within the constructor-valid range for the chosen total supply.
        // The upper bound leaves enough room for at least one initialized tick above the floor.
        deploymentParams.auctionParams.floorPrice = ConstantsLib.MIN_FLOOR_PRICE
            + (seededUint256(seed, 'floorPrice') % (maxFloorPrice - ConstantsLib.MIN_FLOOR_PRICE + 1));
        deploymentParams.auctionParams.tickSpacing =
            (uint256(deploymentParams.auctionParams.floorPrice) * tickSpacingBps) / BPS;
        if (deploymentParams.auctionParams.tickSpacing < ConstantsLib.MIN_TICK_SPACING) {
            deploymentParams.auctionParams.tickSpacing = ConstantsLib.MIN_TICK_SPACING;
        }

        deploymentParams.auctionParams.floorPrice = roundPriceDownToTickSpacing(
            deploymentParams.auctionParams.floorPrice, deploymentParams.auctionParams.tickSpacing
        );
        if (deploymentParams.auctionParams.floorPrice < ConstantsLib.MIN_FLOOR_PRICE) {
            deploymentParams.auctionParams.floorPrice =
                roundPriceUpToTickSpacing(ConstantsLib.MIN_FLOOR_PRICE, deploymentParams.auctionParams.tickSpacing);
        }
        deploymentParams.auctionParams.requiredCurrencyRaised = fixtureRequiredCurrencyRaised(
            seededUint256(seed, 'requiredCurrencyRaised'),
            deploymentParams.totalSupply,
            deploymentParams.auctionParams.floorPrice
        );

        uint256 latestStartBlock = type(uint64).max - deploymentParams.numberOfSteps - 2;
        currentBlock = FixedPointMathLib.min(currentBlock, latestStartBlock);
        deploymentParams.auctionParams.startBlock =
            uint64(currentBlock + (seededUint256(seed, 'startBlock') % (latestStartBlock - currentBlock + 1)));
        deploymentParams.auctionParams.endBlock =
            deploymentParams.auctionParams.startBlock + uint64(deploymentParams.numberOfSteps);
        deploymentParams.auctionParams.claimBlock = deploymentParams.auctionParams.endBlock + 1;
        deploymentParams.auctionParams.auctionStepsData = generateAuctionSteps(deploymentParams.numberOfSteps);
    }

    /// @notice Generate a tick-aligned bid price strictly above clearing and within max price.
    /// @return maxPrice The generated price, or zero when no valid higher tick exists.
    /// @return canBid Whether a valid price was generated.
    function nextBidPrice(uint256 clearingPrice, uint256 tickSpacing, uint256 maxBidPrice, uint8 tickNumber)
        internal
        pure
        returns (uint256, bool)
    {
        uint256 remainder = clearingPrice % tickSpacing;
        uint256 priceDelta = remainder == 0 ? tickSpacing : tickSpacing - remainder;
        if (priceDelta > maxBidPrice) return (0, false);
        if (clearingPrice > maxBidPrice - priceDelta) return (0, false);
        uint256 minimumBidPrice = clearingPrice + priceDelta;
        if (minimumBidPrice > maxBidPrice) return (0, false);

        uint256 maxOffset = (maxBidPrice - minimumBidPrice) / tickSpacing;
        uint256 maxSelectableOffset = FixedPointMathLib.min(maxOffset, type(uint8).max);
        uint256 offset = uint256(tickNumber) % (maxSelectableOffset + 1);
        return (minimumBidPrice + offset * tickSpacing, true);
    }

    /// @notice Generate a bid token amount from a seed.
    /// @dev Distribution:
    ///      - 8% exact edge values: 0, 1, 2, max-1, max.
    ///      - 10% tiny/dust values near zero.
    ///      - 77% typical fixture-sized values across common 18-decimal token scales.
    ///      - 5% large values across the full uint128 input space.
    ///      The output is intentionally not bounded by auction supply or remaining supply; callers
    ///      should let protocol validation handle unreasonable values.
    function seededBidTokenAmount(uint128 amountSeed) internal pure returns (uint128) {
        uint256 bucket = uint256(amountSeed) % 100;

        if (bucket < 8) {
            uint128[8] memory edgeAmounts = [
                uint128(0),
                uint128(1),
                uint128(2),
                uint128(1e6),
                uint128(1e18),
                type(uint128).max - 1,
                type(uint128).max,
                uint128(seededUint256(amountSeed, 'edge'))
            ];
            return edgeAmounts[bucket];
        } else if (bucket < 18) {
            return uint128(seededUint256(amountSeed, 'tiny') % 1e18);
        } else if (bucket >= 95) {
            return uint128(seededUint256(amountSeed, 'large'));
        } else {
            uint128[8] memory anchors = [
                uint128(1e18),
                uint128(10e18),
                uint128(100e18),
                uint128(1000e18),
                uint128(10_000e18),
                uint128(100_000e18),
                uint128(1_000_000e18),
                uint128(1_000_000_000e18)
            ];
            uint256 anchor = anchors[seededUint256(amountSeed, 'normalAnchor') % anchors.length];
            uint256 jitter = seededUint256(amountSeed, 'normalJitter') % (anchor + 1);
            return SafeCastLib.toUint128(anchor + jitter);
        }
    }

    /// @notice Convert a desired token amount into the bid input amount at maxPrice.
    /// @dev Saturates at uint128.max because submitBid accepts uint128 input amounts.
    function inputAmountForTokens(uint128 tokenAmount, uint256 maxPrice) internal pure returns (uint128) {
        if (tokenAmount > (type(uint128).max * FixedPoint96.Q96) / maxPrice) {
            return type(uint128).max;
        }
        return SafeCastLib.toUint128(uint256(tokenAmount).fullMulDivUp(maxPrice, FixedPoint96.Q96));
    }

    /// @notice Round price down to the nearest tick boundary.
    function roundPriceDownToTickSpacing(uint256 price, uint256 tickSpacing) internal pure returns (uint256) {
        return price - (price % tickSpacing);
    }

    /// @notice Round price up to the nearest tick boundary.
    function roundPriceUpToTickSpacing(uint256 price, uint256 tickSpacing) internal pure returns (uint256) {
        uint256 remainder = price % tickSpacing;
        if (remainder == 0) return price;
        return price + (tickSpacing - remainder);
    }

    /// @notice Generate a linear auction step schedule split evenly across numberOfSteps.
    function generateAuctionSteps(uint256 numberOfSteps) internal pure returns (bytes memory) {
        uint256 mpsPerStep = ConstantsLib.MPS / numberOfSteps;
        bytes memory stepsData = new bytes(0);
        for (uint8 i = 0; i < numberOfSteps; i++) {
            stepsData = AuctionStepsBuilder.addStep(stepsData, uint24(mpsPerStep), uint40(1));
        }
        return stepsData;
    }
}
