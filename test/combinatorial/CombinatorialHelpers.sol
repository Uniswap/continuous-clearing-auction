// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Auction} from '../../src/Auction.sol';

import {Checkpoint} from '../../src/libraries/CheckpointLib.sol';

import {Bid, BidLib} from '../../src/libraries/BidLib.sol';
import {ConstantsLib} from '../../src/libraries/ConstantsLib.sol';
import {FixedPoint96} from '../../src/libraries/FixedPoint96.sol';
import {FixedPointMathLib} from 'solady/utils/FixedPointMathLib.sol';

import {ValueX7, ValueX7Lib} from '../../src/libraries/ValueX7Lib.sol';
import {AuctionBaseTest} from '../utils/AuctionBaseTest.sol';
import {FuzzBid} from '../utils/FuzzStructs.sol';
import {ExitPath, PostBidScenario, PreBidScenario} from './CombinatorialEnums.sol';

import {Test} from 'forge-std/Test.sol';
import {console} from 'forge-std/console.sol';

contract CombinatorialHelpers is AuctionBaseTest {
    using BidLib for Bid;
    using ValueX7Lib for ValueX7;
    using ValueX7Lib for uint256;
    using FixedPointMathLib for uint256;

    // Constants for safe arithmetic

    uint256 internal constant Q96_OVERFLOW_THRESHOLD = type(uint256).max / (1 << 96);
    uint256 internal constant MUL_OVERFLOW_CHECK = type(uint256).max / 10_000_000; // ConstantsLib.MPS
    uint256 internal constant CHECKPOINT_TRAVERSAL_LIMIT = 10_000; // Safety limit for linked list

    // ===== SCENARIO HELPERS =====
    function helper__preBidScenario(PreBidScenario scenario, uint256 userMaxPrice, bool Q96) public {
        console.log('helper__preBidScenario: Starting pre bid scenario');
        console.log('helper__preBidScenario: scenario', uint8(scenario));
        console.log('helper__preBidScenario: userMaxPrice', userMaxPrice);
        console.log('helper__preBidScenario: Q96', Q96);

        uint256 tickSpacing = Q96 ? auction.tickSpacing() : auction.tickSpacing() >> FixedPoint96.RESOLUTION;
        uint256 floorPrice = Q96 ? auction.floorPrice() : auction.floorPrice() >> FixedPoint96.RESOLUTION;

        if (userMaxPrice % tickSpacing != 0) {
            revert('preBidScenario: userMaxPrice not compliant with tickSpacing');
        }

        if (scenario == PreBidScenario.NoBidsBeforeUser) {
            // No action needed - auction starts with no bids
            return;
        } else if (scenario == PreBidScenario.BidsBeforeUser) {
            // Place bids that raise clearing price, but keep it below userMaxPrice
            // Move clearing to midpoint between floor and userMaxPrice
            uint256 targetClearingPrice;
            if (userMaxPrice > floorPrice + tickSpacing * 2) {
                // Place clearing at least 2 ticks below userMaxPrice
                targetClearingPrice = userMaxPrice - (2 * tickSpacing);
                helper__setAuctionClearingPrice(targetClearingPrice, new address[](1), Q96);
            } else {
                // userMaxPrice is too close to floor, just keep at floor
                return;
            }
        } else if (scenario == PreBidScenario.ClearingPriceBelowMaxPrice) {
            // Raise clearing price to exactly one tick below userMaxPrice
            if (userMaxPrice > floorPrice + tickSpacing) {
                uint256 targetClearingPrice = userMaxPrice - tickSpacing;
                helper__setAuctionClearingPrice(targetClearingPrice, new address[](1), Q96);
                return;
            } else {
                // userMaxPrice is already only one tick above floor, just keep at floor
                return;
            }
        } else if (scenario == PreBidScenario.BidsAtClearingPrice) {
            // First, move clearing price to one tick below userMaxPrice
            if (userMaxPrice > floorPrice + tickSpacing) {
                uint256 targetClearingPrice = userMaxPrice - tickSpacing;
                helper__setAuctionClearingPrice(targetClearingPrice, new address[](1), Q96);
            }

            // Then place a small bid at exactly userMaxPrice (not large enough to move clearing)
            uint256 smallBidAmount = 0.01 ether; // Small bid amount
            vm.deal(address(this), smallBidAmount);
            auction.submitBid{value: smallBidAmount}(
                userMaxPrice << (Q96 ? 0 : FixedPoint96.RESOLUTION), uint128(smallBidAmount), address(this), bytes('')
            );
            return;
        } else {
            revert('Invalid pre bid scenario');
        }
    }

    function helper__postBidScenario(
        PostBidScenario scenario,
        uint256 userMaxPrice,
        bool Q96,
        uint64 bidDelay,
        uint256 clearingPriceFillPercentage
    ) public returns (PostBidScenario actualScenario) {
        console.log('helper__postBidScenario: Starting post bid scenario');
        console.log('helper__postBidScenario: scenario', uint8(scenario));
        console.log('helper__postBidScenario: userMaxPrice', userMaxPrice);
        console.log('helper__postBidScenario: Q96', Q96);

        uint256 tickSpacing = Q96 ? auction.tickSpacing() : auction.tickSpacing() >> FixedPoint96.RESOLUTION;
        if (userMaxPrice % tickSpacing != 0) {
            revert('postBidScenario: userMaxPrice not compliant with tickSpacing');
        }

        uint256 snap = vm.snapshot();
        vm.roll(block.number + 1);
        auction.checkpoint();
        uint256 clearingPrice = Q96 ? auction.clearingPrice() : auction.clearingPrice() >> FixedPoint96.RESOLUTION;
        vm.revertToState(snap);

        if (scenario == PostBidScenario.NoBidsAfterUser) {
            return PostBidScenario.NoBidsAfterUser; // Scenario successfully "set up" (no action needed)
        } else if (scenario == PostBidScenario.UserAboveClearing) {
            if (userMaxPrice <= clearingPrice + tickSpacing) {
                // User's bid is at or right above the clearing price
                return PostBidScenario.NoBidsAfterUser;
            } else {
                // User's bid is more then one tick above clearing: Move clearing right below the user's bid
                helper__setAuctionClearingPrice(userMaxPrice - tickSpacing, new address[](1), Q96);
                return PostBidScenario.UserAboveClearing;
            }
        } else if (scenario == PostBidScenario.UserAtClearing) {
            if (userMaxPrice <= clearingPrice) {
                // User's bid is already at clearing price or outbid
                return PostBidScenario.NoBidsAfterUser;
            } else {
                // User's bid is more then one tick above clearing: Move clearing right below the user's bid
                if (auction.endBlock() <= block.number + bidDelay) {
                    // The next block is past the auction, so no bids will be placed
                    return PostBidScenario.NoBidsAfterUser;
                }
                vm.roll(block.number + bidDelay); // Outbid in the next block
                helper__setAuctionClearingPrice(userMaxPrice, new address[](1), Q96);
                if (clearingPriceFillPercentage > 0) {
                    helper__setAuctionClearingPrice(
                        userMaxPrice + tickSpacing, new address[](1), Q96, clearingPriceFillPercentage
                    );
                }
                return PostBidScenario.UserAtClearing;
            }
        } else if (scenario == PostBidScenario.UserOutbidLater) {
            if (userMaxPrice < clearingPrice) {
                // User's bid is already below the clearing price
                return PostBidScenario.NoBidsAfterUser;
            } else {
                // User's bid is above or equal to the clearing price: Move clearing above the user's bid
                if (auction.endBlock() <= block.number + bidDelay) {
                    // The next block is past the auction, so no bids will be placed
                    return PostBidScenario.NoBidsAfterUser;
                }
                vm.roll(block.number + bidDelay); // Outbid in the next block
                helper__setAuctionClearingPrice(userMaxPrice + tickSpacing, new address[](1), Q96);
                return PostBidScenario.UserOutbidLater;
            }
        } else if (scenario == PostBidScenario.UserOutbidImmediately) {
            if (userMaxPrice < clearingPrice) {
                // User's bid is already below the clearing price
                return PostBidScenario.NoBidsAfterUser;
            } else {
                // User's bid is above or equal to the clearing price: Move clearing above the user's bid immediately
                helper__setAuctionClearingPrice(userMaxPrice + tickSpacing, new address[](1), Q96);
                return PostBidScenario.UserOutbidImmediately;
            }
        } else {
            revert('Invalid post bid scenario');
        }
    }

    function helper__setAuctionClearingPrice(uint256 targetClearingPrice, address[] memory bidOwners, bool Q96)
        public
        returns (bool success)
    {
        return helper__setAuctionClearingPrice(targetClearingPrice, bidOwners, Q96, ConstantsLib.MPS);
    }

    function helper__setAuctionClearingPrice(
        uint256 targetClearingPrice,
        address[] memory bidOwners,
        bool Q96,
        uint256 clearingPriceFillPercentage
    ) public returns (bool success) {
        if (clearingPriceFillPercentage > ConstantsLib.MPS) {
            revert('clearingPriceFillPercentage is greater than ConstantsLib.MPS');
        }
        Checkpoint memory checkpoint = auction.checkpoint();

        uint256 clearingPrice = Q96 ? auction.clearingPrice() : auction.clearingPrice() >> FixedPoint96.RESOLUTION;
        if (clearingPrice > targetClearingPrice) {
            return false; // Clearing price is already greater than target clearing price
        } else if (clearingPrice == targetClearingPrice) {
            return true;
        } else {
            uint256 bidAmountToMoveToTargetClearingPrice;
            // Calculate the bid amount to move to the target clearing price
            {
                uint256 totalSupply_ = auction.totalSupply();

                /*
                // Calculate remaining supply (amount not yet sold)
                uint256 remainingSupply =
                    totalSupply_ - totalSupply_.fullMulDiv(checkpoint.cumulativeMps, ConstantsLib.MPS);

                // TEMP force clearingPercentage
                if (clearingPriceFillPercentage < ConstantsLib.MPS) {
                    clearingPriceFillPercentage = 9_500_000;

                    auction.bids(0); // PreBidScenario
                    auction.bids(1); // Users Bid
                    auction.bids(2); // Moved Clearing Price
                    auction.nextBidId();
                    console.log('targetClearingPrice', targetClearingPrice);
                    console.log('cumulativeMps', checkpoint.cumulativeMps);
                }

                // TODO: a low clearingPriceFillPercentage indeed increases the fillRatioPercent of the user (less demand, more left over for the user),
                // while a high clearingPriceFillPercentage decreases the fillRatioPercent of the user (more demand, less left over for the user).
                // But why is a clearingPriceFillPercentage of 9_500_000 already moving the clearing price up???

                // Use fullMulDiv to prevent overflow during multiplication
                // bidAmount = remainingSupply * targetClearingPrice / (Q96 ? Q96 : 1)
                bidAmountToMoveToTargetClearingPrice =
                    remainingSupply.fullMulDivUp(targetClearingPrice, Q96 ? FixedPoint96.Q96 : 1);
                // Scale the bid amount to the clearing price fill percentage
                bidAmountToMoveToTargetClearingPrice =
                    bidAmountToMoveToTargetClearingPrice.fullMulDiv(clearingPriceFillPercentage, ConstantsLib.MPS);
                    */

                /* TEST --- */
                if (clearingPriceFillPercentage < ConstantsLib.MPS) {
                    clearingPriceFillPercentage = 9_500_000;
                    auction.bids(0); // PreBidScenario
                    auction.bids(1); // Users Bid
                    auction.bids(2); // Moved Clearing Price
                    auction.nextBidId();
                    console.log('targetClearingPrice', targetClearingPrice);
                }
                uint256 bidAmountToMoveToTargetClearingPriceQ96 = totalSupply_ * targetClearingPrice;
                // Scale to fill percentage
                bidAmountToMoveToTargetClearingPriceQ96 =
                    bidAmountToMoveToTargetClearingPriceQ96.fullMulDiv(clearingPriceFillPercentage, ConstantsLib.MPS);
                // Scale down to remaining supply
                uint256 remainingSupplyPercentage = ConstantsLib.MPS - checkpoint.cumulativeMps;
                bidAmountToMoveToTargetClearingPriceQ96 =
                    bidAmountToMoveToTargetClearingPriceQ96.fullMulDiv(remainingSupplyPercentage, ConstantsLib.MPS);
                bidAmountToMoveToTargetClearingPrice =
                    bidAmountToMoveToTargetClearingPriceQ96 >> (Q96 ? FixedPoint96.RESOLUTION : 0);
                /* TEST END */
            }
            if (bidAmountToMoveToTargetClearingPrice > uint256(type(uint128).max)) {
                revert('Bid amount to move to target clearing price is too large');
            }

            vm.deal(address(this), bidAmountToMoveToTargetClearingPrice);
            uint256 allBidAmounts = 0;
            uint256 i = 0;
            while (bidOwners.length > 0) {
                uint256 bidAmount = bidAmountToMoveToTargetClearingPrice / bidOwners.length;
                allBidAmounts += bidAmount;
                if (i == bidOwners.length - 1) {
                    // last bid, add the remaining bid amount
                    bidAmount += bidAmountToMoveToTargetClearingPrice - allBidAmounts;
                }
                if (bidAmount == 0) {
                    break;
                }
                address bidOwner = bidOwners[i];
                try auction.submitBid{value: bidAmount}(
                    targetClearingPrice << (Q96 ? 0 : FixedPoint96.RESOLUTION), uint128(bidAmount), bidOwner, bytes('')
                ) returns (uint256 bidId) {
                    // vm.roll(block.number + 1);
                    // auction.checkpoint();
                    console.log('BID', auction.bids(bidId).startCumulativeMps);
                } catch (bytes memory) {
                    return false;
                }

                i++;
                if (i >= bidOwners.length) {
                    break;
                }
            }
            return true;
        }
    }

    // ===== VERIFICATION HELPERS =====

    /// @notice Verify a non-graduated auction exit (full refund)
    /// @param bidId The bid ID to exit
    /// @param balanceBefore Currency balance before exit
    /// @param expectedAmount Expected refund amount (should equal original bid amount)
    function helper__verifyNonGraduatedExit(uint256 bidId, uint256 balanceBefore, uint256 expectedAmount) internal {
        console.log('Verifying non-graduated exit for bidId:', bidId);

        // Get bid info before exit
        Bid memory bidBefore = auction.bids(bidId);
        address bidOwner = bidBefore.owner;

        // Exit should succeed
        try auction.exitBid(bidId) {
            // Verify bid was exited
            Bid memory bidAfter = auction.bids(bidId);
            assertEq(bidAfter.exitedBlock, uint64(block.number), 'Exit block not set');
            assertEq(bidAfter.tokensFilled, 0, 'Non-graduated should have 0 tokens filled');

            // Verify full refund (exact amount, not Q96)
            uint256 balanceAfter = address(bidOwner).balance;
            uint256 actualRefund = balanceAfter - balanceBefore;
            uint256 expectedRefund = bidBefore.amountQ96 >> FixedPoint96.RESOLUTION;

            assertEq(actualRefund, expectedRefund, 'Non-graduated refund mismatch');
            assertEq(actualRefund, expectedAmount, 'Refund should match expected amount');

            console.log('  Refund:', actualRefund);
            console.log('  Non-graduated exit verified successfully');
        } catch (bytes memory err) {
            console.log('  Exit failed:');
            console.logBytes(err);
            revert('Non-graduated exitBid failed');
        }
    }

    /// @notice Verify a partial exit (outbid mid-auction or at clearing at end)
    /// @param bidId The bid ID to exit
    /// @return currencySpentQ96 The actual currency spent in Q96 format (for metrics)
    function helper__verifyPartialExit(uint256 bidId) internal returns (uint256 currencySpentQ96) {
        console.log('Verifying partial exit for bidId:', bidId);

        // Get bid info
        Bid memory bid = auction.bids(bidId);
        address bidOwner = bid.owner;
        uint256 balanceBefore = address(bidOwner).balance;

        // Get checkpoints
        Checkpoint memory startCP = auction.checkpoints(bid.startBlock);

        // Find hints using robust checkpoint inspection
        (uint64 lastFullyFilledBlock,, bool notFullyFilled) = helper__findLastFullyFilledCheckpoint(bid);
        (uint64 outbidBlock, bool wasOutbid) = helper__findOutbidBlock(bid);

        if (!notFullyFilled && !wasOutbid) {
            revert('Bid was fully filled and not outbid');
        }

        // Calculate expected outcome using two-phase approach
        (uint256 expectedTokens, uint256 expectedCurrencyQ96) =
            helper__calculatePartiallyFilledOutcome(bid, startCP, lastFullyFilledBlock, outbidBlock);

        // Exit the bid
        try auction.exitPartiallyFilledBid(bidId, lastFullyFilledBlock, outbidBlock) {
            // Verify bid exit state
            Bid memory bidAfter = auction.bids(bidId);
            assertEq(bidAfter.exitedBlock, uint64(block.number), 'Exit block not set');

            // Verify tokens filled with tolerance
            uint256 tolerance = 0; // 0% tolerance
            assertApproxEqAbs(bidAfter.tokensFilled, expectedTokens, tolerance, 'Partial exit tokens mismatch');

            // Verify refund
            uint256 balanceAfter = address(bidOwner).balance;
            uint256 actualRefund = balanceAfter - balanceBefore;
            uint256 expectedRefund = (bid.amountQ96 - expectedCurrencyQ96) >> FixedPoint96.RESOLUTION;

            // Allow tolerance for Q96 + pro-rata rounding
            uint256 refundTolerance = 0; // 0 tolerance
            assertApproxEqAbs(actualRefund, expectedRefund, refundTolerance, 'Partial exit refund mismatch');

            console.log('  Tokens filled:', bidAfter.tokensFilled);
            console.log('  Expected tokens:', expectedTokens);
            console.log('  Refund:', actualRefund);
            console.log('  Partial exit verified successfully');

            // Return the actual currency spent for metrics
            return expectedCurrencyQ96;
        } catch (bytes memory err) {
            console.log('  Partial exit failed:');
            console.logBytes(err);

            // Graceful degradation: log warning but don't fail test
            console.log('  WARNING: Partial exit verification failed, but continuing test');
            revert('Partial exit verification failed');
        }
    }

    /// @notice Verify a full exit (bid above clearing at auction end)
    /// @param bidId The bid ID to exit
    /// @param balanceBefore Currency balance before exit
    /// @return currencySpentQ96 The actual currency spent in Q96 format (for metrics)
    function helper__verifyFullExit(uint256 bidId, uint256 balanceBefore) internal returns (uint256 currencySpentQ96) {
        console.log('Verifying full exit for bidId:', bidId);

        // Get bid info
        Bid memory bid = auction.bids(bidId);
        address bidOwner = bid.owner;

        // Get checkpoints for calculation
        Checkpoint memory startCP = auction.checkpoints(bid.startBlock);
        Checkpoint memory finalCP = auction.checkpoints(auction.endBlock());

        // Calculate expected outcome
        (uint256 expectedTokens, uint256 expectedCurrencyQ96) =
            helper__calculateFullyFilledOutcome(bid, startCP, finalCP);

        // Exit the bid
        try auction.exitBid(bidId) {
            // Verify bid exit state
            Bid memory bidAfter = auction.bids(bidId);
            assertEq(bidAfter.exitedBlock, uint64(block.number), 'Exit block not set');
            assertEq(bidAfter.tokensFilled, expectedTokens, 'Tokens filled mismatch');

            // Verify refund
            uint256 balanceAfter = address(bidOwner).balance;
            uint256 actualRefund = balanceAfter - balanceBefore;
            uint256 expectedRefund = (bid.amountQ96 - expectedCurrencyQ96) >> FixedPoint96.RESOLUTION;

            // Allow small tolerance for Q96 rounding
            uint256 tolerance = 0; // 0 wei tolerance
            assertApproxEqAbs(actualRefund, expectedRefund, tolerance, 'Full exit refund mismatch');

            console.log('  Tokens filled:', expectedTokens);
            console.log('  Currency spent (Q96):', expectedCurrencyQ96);
            console.log('  Refund:', actualRefund);
            console.log('  Full exit verified successfully');

            // Return the actual currency spent for metrics
            return expectedCurrencyQ96;
        } catch (bytes memory err) {
            console.log('  Exit failed:');
            console.logBytes(err);
            revert('Full exitBid failed');
        }
    }

    /// @notice Check if Q96 multiplication would overflow
    /// @param a First operand
    /// @param b Second operand
    /// @return True if multiplication is safe
    function helper__checkQ96MulSafe(uint256 a, uint256 b) internal pure returns (bool) {
        if (a == 0 || b == 0) return true;
        if (a > Q96_OVERFLOW_THRESHOLD || b > Q96_OVERFLOW_THRESHOLD) return false;
        // Check actual multiplication
        unchecked {
            uint256 c = a * b;
            if (c / a != b) return false;
        }
        return true;
    }

    /// @notice Classify the exit path for a bid based on final state
    /// @param bid The bid to classify
    /// @param finalCheckpoint The final checkpoint at auction end
    /// @param graduated Whether auction graduated
    /// @return The exit path classification
    function helper__classifyExitPath(Bid memory bid, Checkpoint memory finalCheckpoint, bool graduated)
        internal
        pure
        returns (ExitPath)
    {
        if (!graduated) return ExitPath.NonGraduated;

        // If bid maxPrice > final clearing, bid was fully filled
        if (bid.maxPrice > finalCheckpoint.clearingPrice) {
            return ExitPath.FullExit;
        }

        // If bid maxPrice <= final clearing, partial fill case
        return ExitPath.PartialExit;
    }

    /// @notice Find the last checkpoint where bid was fully filled (clearing < maxPrice)
    /// @dev Returns 0 if bid was never fully filled (at clearing from start)
    /// @param bid The bid to analyze
    /// @return lastFullyFilledBlock The last block where clearing < maxPrice, or 0 if never fully filled
    /// @return notFullyFilledBlock The last block where clearing < maxPrice, or 0 if never fully filled
    /// @return notFullyFilled Whether the bid was never fully filled
    function helper__findLastFullyFilledCheckpoint(Bid memory bid)
        internal
        view
        returns (uint64 lastFullyFilledBlock, uint64 notFullyFilledBlock, bool notFullyFilled)
    {
        uint64 currentBlock = bid.startBlock;

        while (currentBlock != 0 && currentBlock != type(uint64).max) {
            Checkpoint memory currentCP = auction.checkpoints(currentBlock);
            if (currentCP.clearingPrice >= bid.maxPrice) {
                notFullyFilledBlock = currentBlock;
                return (currentCP.prev, notFullyFilledBlock, true);
            }
            currentBlock = currentCP.next;
        }

        // Fully filled
        return (0, 0, false);
    }

    /// @notice Find the block where bid was outbid (clearing > maxPrice)
    /// @dev Returns 0 if bid was never outbid
    /// @dev Special handling for same-block outbids: checks subsequent bids in same block
    /// @param bid The bid to analyze
    /// @return outbidBlock The first block where clearing > maxPrice, or 0 if never outbid
    /// @return wasOutbid Whether the bid was outbid
    function helper__findOutbidBlock(Bid memory bid) internal view returns (uint64 outbidBlock, bool wasOutbid) {
        uint64 currentBlock = bid.startBlock;

        while (currentBlock != 0 && currentBlock != type(uint64).max) {
            Checkpoint memory currentCP = auction.checkpoints(currentBlock);
            if (currentCP.clearingPrice > bid.maxPrice) {
                return (currentBlock, true);
            }
            currentBlock = currentCP.next;
        }

        // Not outbid - ended at or below clearing
        return (0, false);
    }

    /// @notice Find first checkpoint at or after a given block
    /// @dev Handles edge case where exact block doesn't have checkpoint
    /// @param targetBlock The target block number
    /// @return checkpointBlock The first checkpoint block >= targetBlock
    function helper__findCheckpointAtOrAfter(uint64 targetBlock) internal view returns (uint64 checkpointBlock) {
        // Start from last checkpointed block and traverse backwards
        uint64 currentBlock = auction.lastCheckpointedBlock();
        uint256 safetyCounter = 0;

        // If target is after last checkpoint, return last checkpoint
        if (targetBlock >= currentBlock) {
            return currentBlock;
        }

        // Traverse backwards to find checkpoint <= target
        while (currentBlock > targetBlock && safetyCounter < CHECKPOINT_TRAVERSAL_LIMIT) {
            Checkpoint memory cp = auction.checkpoints(currentBlock);
            if (cp.prev == 0) break;
            currentBlock = cp.prev;
            safetyCounter++;
        }

        require(safetyCounter < CHECKPOINT_TRAVERSAL_LIMIT, 'Checkpoint traversal limit exceeded');

        // Now traverse forward to find first >= target
        while (currentBlock < targetBlock && safetyCounter < CHECKPOINT_TRAVERSAL_LIMIT) {
            Checkpoint memory cp = auction.checkpoints(currentBlock);
            if (cp.next == 0) break;
            currentBlock = cp.next;
            safetyCounter++;
        }

        require(safetyCounter < CHECKPOINT_TRAVERSAL_LIMIT, 'Checkpoint traversal limit exceeded');
        return currentBlock;
    }

    /// @notice Verify bid struct properties are correct immediately after submission
    /// @param bidId The ID of the submitted bid
    /// @param expectedOwner Expected owner address
    /// @param expectedMaxPrice Expected max price
    /// @param expectedAmountQ96 Expected amount in Q96
    /// @param expectedStartBlock Expected start block
    function helper__verifyBidStruct(
        uint256 bidId,
        address expectedOwner,
        uint256 expectedMaxPrice,
        uint256 expectedAmountQ96,
        uint64 expectedStartBlock
    ) internal view {
        Bid memory bid = auction.bids(bidId);

        // Verify basic bid properties
        assertEq(bid.owner, expectedOwner, 'Bid owner mismatch');
        assertEq(bid.maxPrice, expectedMaxPrice, 'Bid maxPrice mismatch');
        assertEq(bid.amountQ96, expectedAmountQ96, 'Bid amountQ96 mismatch');
        assertEq(bid.startBlock, expectedStartBlock, 'Bid startBlock mismatch');
        assertEq(bid.exitedBlock, 0, 'Bid should not be exited yet');
        assertEq(bid.tokensFilled, 0, 'Bid should have no tokens filled yet');

        // Verify startCumulativeMps matches checkpoint
        Checkpoint memory startCP = auction.checkpoints(expectedStartBlock);
        assertEq(bid.startCumulativeMps, startCP.cumulativeMps, 'Bid startCumulativeMps should match checkpoint');

        console.log('Bid struct verification passed for bidId:', bidId);
    }

    /// @notice Calculate expected outcome for fully filled bid
    /// @dev Uses checkpoint cumulative deltas - this is exact (no approximation)
    /// @param bid The bid to calculate for
    /// @param startCheckpoint Checkpoint at bid submission
    /// @param finalCheckpoint Final checkpoint at auction end
    /// @return expectedTokensFilled Expected tokens filled
    /// @return expectedCurrencySpent Expected currency spent in Q96
    function helper__calculateFullyFilledOutcome(
        Bid memory bid,
        Checkpoint memory startCheckpoint,
        Checkpoint memory finalCheckpoint
    ) internal pure returns (uint256 expectedTokensFilled, uint256 expectedCurrencySpent) {
        // Calculate cumulative deltas
        uint24 cumulativeMpsDelta = finalCheckpoint.cumulativeMps - startCheckpoint.cumulativeMps;
        uint256 cumulativeMpsPerPriceDelta =
            finalCheckpoint.cumulativeMpsPerPrice - startCheckpoint.cumulativeMpsPerPrice;

        // Use the same calculation as CheckpointStorage._calculateFill
        uint24 mpsRemaining = ConstantsLib.MPS - bid.startCumulativeMps;

        // Currency spent = bid amount * (mps delta / mps remaining)
        // Using fullMulDivUp handles large multiplications safely without overflow
        expectedCurrencySpent = bid.amountQ96.fullMulDivUp(cumulativeMpsDelta, mpsRemaining);

        // Tokens filled uses effective amount and harmonic mean
        // Using fullMulDiv handles large multiplications safely without overflow
        expectedTokensFilled = bid.amountQ96.fullMulDiv(
            cumulativeMpsPerPriceDelta, (FixedPoint96.Q96 << FixedPoint96.RESOLUTION) * mpsRemaining
        );

        console.log('Full exit calculation:');
        console.log('  cumulativeMpsDelta:', cumulativeMpsDelta);
        console.log('  expectedTokensFilled:', expectedTokensFilled);
        console.log('  expectedCurrencySpent (Q96):', expectedCurrencySpent);
    }

    /// @notice Calculate expected outcome for partially filled bid
    /// @dev Two-phase calculation: Phase 1 (fully-filled period) + Phase 2 (partially-filled period)
    /// @param bid The bid to calculate for
    /// @param startCheckpoint Checkpoint at bid submission
    /// @param lastFullyFilledBlock Last block where clearing < maxPrice (0 if never fully filled)
    /// @param outbidBlock Block where clearing > maxPrice (0 if not outbid)
    /// @return expectedTokensFilled Expected tokens filled
    /// @return expectedCurrencySpent Expected currency spent in Q96
    function helper__calculatePartiallyFilledOutcome(
        Bid memory bid,
        Checkpoint memory startCheckpoint,
        uint64 lastFullyFilledBlock,
        uint64 outbidBlock
    ) internal view returns (uint256 expectedTokensFilled, uint256 expectedCurrencySpent) {
        uint256 phase1Tokens = 0;
        uint256 phase1Currency = 0;

        // PHASE 1: Fully-filled period (if any exists)
        if (lastFullyFilledBlock > bid.startBlock) {
            Checkpoint memory lastFullyFilledCP = auction.checkpoints(lastFullyFilledBlock);

            // Use full exit calculation for the fully-filled portion
            (phase1Tokens, phase1Currency) =
                helper__calculateFullyFilledOutcome(bid, startCheckpoint, lastFullyFilledCP);

            console.log('Phase 1 (fully-filled):');
            console.log('  lastFullyFilledBlock:', lastFullyFilledBlock);
            console.log('  tokens:', phase1Tokens);
            console.log('  currency (Q96):', phase1Currency);
        } else if (lastFullyFilledBlock == 0) {
            console.log('Phase 1: Skipped (at clearing from start)');
        } else {
            console.log('Phase 1: Skipped (immediately partial)');
        }

        // PHASE 2: Partially-filled period
        uint256 phase2Tokens = 0;
        uint256 phase2Currency = 0;

        if (outbidBlock > 0) {
            // Case A: Outbid mid-auction
            console.log('Phase 2 (outbid mid-auction):');

            // Find the checkpoint just before outbid
            Checkpoint memory outbidCP = auction.checkpoints(outbidBlock);
            uint64 partialFilledBlock = outbidCP.prev;

            if (partialFilledBlock >= bid.startBlock) {
                Checkpoint memory partialCP = auction.checkpoints(partialFilledBlock);

                // Bid was at clearing price during this checkpoint
                if (partialCP.clearingPrice == bid.maxPrice) {
                    (phase2Tokens, phase2Currency) = helper__calculatePartialFillAtClearing(bid, partialCP);
                }
            }

            console.log('  outbidBlock:', outbidBlock);
            console.log('  tokens:', phase2Tokens);
            console.log('  currency (Q96):', phase2Currency);
        } else {
            // Case B: At clearing at auction end (not outbid)
            console.log('Phase 2 (at clearing at end):');

            Checkpoint memory finalCP = auction.checkpoints(auction.endBlock());

            if (finalCP.clearingPrice == bid.maxPrice) {
                (phase2Tokens, phase2Currency) = helper__calculatePartialFillAtClearing(bid, finalCP);
            }

            console.log('  finalBlock:', auction.endBlock());
            console.log('  tokens:', phase2Tokens);
            console.log('  currency (Q96):', phase2Currency);
        }

        // Combine both phases
        expectedTokensFilled = phase1Tokens + phase2Tokens;
        expectedCurrencySpent = phase1Currency + phase2Currency;

        console.log('Total partial exit:');
        console.log('  expectedTokensFilled:', expectedTokensFilled);
        console.log('  expectedCurrencySpent (Q96):', expectedCurrencySpent);
    }

    /// @notice Calculate partial fill at clearing price using pro-rata allocation
    /// @dev Replicates CheckpointStorage._accountPartiallyFilledCheckpoints logic
    /// @param bid The bid to calculate for
    /// @param checkpointAtClearing Checkpoint where bid is at clearing price
    /// @return tokensFilled Tokens filled during partial period
    /// @return currencySpent Currency spent in Q96
    function helper__calculatePartialFillAtClearing(Bid memory bid, Checkpoint memory checkpointAtClearing)
        internal
        view
        returns (uint256 tokensFilled, uint256 currencySpent)
    {
        // Get total demand at the clearing price tick
        uint256 tickDemandQ96 = auction.ticks(bid.maxPrice).currencyDemandQ96;

        if (tickDemandQ96 == 0) {
            return (0, 0);
        }

        // Get cumulative currency raised at clearing price
        ValueX7 currencyRaisedAtClearingQ96_X7 = checkpointAtClearing.currencyRaisedAtClearingPriceQ96_X7;

        // Calculate bid's share using pro-rata allocation
        // This matches CheckpointStorage._accountPartiallyFilledCheckpoints exactly
        uint24 mpsRemaining = ConstantsLib.MPS - bid.startCumulativeMps;

        // Scale up bid amount and apply pro-rata
        ValueX7 currencySpentQ96_X7 = bid.amountQ96.scaleUpToX7().fullMulDivUp(
            currencyRaisedAtClearingQ96_X7, ValueX7.wrap(tickDemandQ96 * mpsRemaining)
        );

        // Scale down to uint256
        currencySpent = currencySpentQ96_X7.scaleDownToUint256();

        // Calculate tokens from currency spent
        tokensFilled = currencySpentQ96_X7.divUint256(bid.maxPrice).scaleDownToUint256();
    }

    /// @notice Validate that actual auction state matches intended scenario
    /// @dev Detects silent failures in helper__postBidScenario()
    /// @param intendedScenario The scenario we tried to set up
    /// @param userBidId The ID of the user's bid
    /// @param finalCheckpoint Final checkpoint at auction end
    function helper__validateScenarioMatchesReality(
        PostBidScenario intendedScenario,
        uint256 userBidId,
        Checkpoint memory finalCheckpoint
    ) internal view {
        PostBidScenario actualScenario;
        uint256 finalClearing = finalCheckpoint.clearingPrice;
        console.log('finalClearing', finalClearing);

        Bid memory bid = auction.bids(userBidId);

        // Determine actual scenario from final state
        // Check if any bids were placed after the user's bid
        bool noBidsAfter = (auction.nextBidId() == userBidId + 1);

        if (noBidsAfter) {
            actualScenario = PostBidScenario.NoBidsAfterUser;
        } else if (bid.maxPrice > finalClearing) {
            actualScenario = PostBidScenario.UserAboveClearing;
        } else if (bid.maxPrice == finalClearing) {
            actualScenario = PostBidScenario.UserAtClearing;
        } else {
            // User was outbid - check timing
            // Find first bid after user that could have outbid them
            uint256 checkBidId = userBidId + 1;
            bool outbidImmediately = false;

            // Look for a bid in the same block with higher price
            while (checkBidId < auction.nextBidId()) {
                Bid memory checkBid = auction.bids(checkBidId);
                if (checkBid.maxPrice > bid.maxPrice) {
                    if (checkBid.startBlock == bid.startBlock) {
                        outbidImmediately = true;
                    }
                    break;
                }
                checkBidId++;
            }

            actualScenario = outbidImmediately ? PostBidScenario.UserOutbidImmediately : PostBidScenario.UserOutbidLater;
        }

        if (actualScenario != intendedScenario) {
            console.log('Actual scenario:', uint8(actualScenario));
            console.log('Intended scenario:', uint8(intendedScenario));
            revert('Scenario mismatch detected');
        }
    }
}
