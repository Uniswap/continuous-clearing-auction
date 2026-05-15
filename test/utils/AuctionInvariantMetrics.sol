// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Vm} from 'forge-std/Vm.sol';

/// @notice Flat run-level metrics emitted by the auction invariant metrics campaign.
/// @dev Keep this struct append-only where possible so downstream JSONL consumers can tolerate upgrades.
struct AuctionInvariantRunMetrics {
    string testName;
    string invariantName;
    bytes32 runId;
    bool initialized;
    bool graduated;
    address auction;
    uint256 deploymentSeed;
    uint256 blockNumber;
    uint256 callCount;
    uint256 startBlock;
    uint256 endBlock;
    uint256 claimBlock;
    uint256 lastCheckpointedBlock;
    uint256 totalSupply;
    uint256 numberOfSteps;
    uint256 floorPrice;
    uint256 tickSpacing;
    uint256 clearingPrice;
    uint256 totalCleared;
    uint256 remainingSupply;
    uint256 currencyRaised;
    uint256 totalCurrencyRaised;
    uint256 bidCount;
    uint256 cntBidEarlyExited;
    uint256 cntBidExited;
    uint256 cntCheckpoints;
    uint256 cntClearingPriceUpdated;
    uint256 cntUntilTickPriceMaxTickPtr;
    uint256 cntUntilTickPrice;
    uint256 cntSubmitBidSkippedMaxPrice;
    uint256 cntSubmitBidSkippedSoldOut;
    uint256 cntSubmitBidSkippedAuctionFinished;
    uint256 cntNonGraduatedBidExited;
    uint256 cntClaimTokensBatchNotGraduated;
    uint256 cntAuctionIsOverError;
    uint256 cntBidAmountTooSmallError;
    uint256 cntTickPriceNotIncreasingError;
    uint256 cntInvalidBidUnableToClearError;
    uint256 cntBidMustBeAboveClearingPriceError;
    uint256 cntNoBidToEarlyExitError;
    uint256 cntBidAlreadyExitedError;
}

/// @notice Utilities for run-level auction invariant metrics.
library AuctionInvariantMetricsLib {
    /// @notice Derive a stable fingerprint for a run summary.
    /// @dev This is not a Foundry run index; it is a content fingerprint that helps de-duplicate rows.
    function runId(AuctionInvariantRunMetrics memory metrics) internal pure returns (bytes32) {
        bytes32 configHash = keccak256(
            abi.encode(
                metrics.auction,
                metrics.deploymentSeed,
                metrics.blockNumber,
                metrics.callCount,
                metrics.totalSupply,
                metrics.numberOfSteps,
                metrics.floorPrice,
                metrics.tickSpacing
            )
        );
        bytes32 stateHash = keccak256(
            abi.encode(
                metrics.clearingPrice,
                metrics.totalCleared,
                metrics.remainingSupply,
                metrics.currencyRaised,
                metrics.totalCurrencyRaised,
                metrics.bidCount
            )
        );
        bytes32 actionCountersHash = keccak256(
            abi.encode(
                metrics.cntBidEarlyExited,
                metrics.cntBidExited,
                metrics.cntCheckpoints,
                metrics.cntClearingPriceUpdated,
                metrics.cntUntilTickPriceMaxTickPtr,
                metrics.cntUntilTickPrice,
                metrics.cntSubmitBidSkippedMaxPrice,
                metrics.cntSubmitBidSkippedSoldOut,
                metrics.cntSubmitBidSkippedAuctionFinished,
                metrics.cntNonGraduatedBidExited,
                metrics.cntClaimTokensBatchNotGraduated
            )
        );
        bytes32 errorCountersHash = keccak256(
            abi.encode(
                metrics.cntAuctionIsOverError,
                metrics.cntBidAmountTooSmallError,
                metrics.cntTickPriceNotIncreasingError,
                metrics.cntInvalidBidUnableToClearError,
                metrics.cntBidMustBeAboveClearingPriceError,
                metrics.cntNoBidToEarlyExitError,
                metrics.cntBidAlreadyExitedError
            )
        );
        return keccak256(
            abi.encode(
                metrics.testName, metrics.invariantName, configHash, stateHash, actionCountersHash, errorCountersHash
            )
        );
    }

    /// @notice Serialize a metrics snapshot as one JSON object suitable for JSONL output.
    /// @dev The object key includes the run fingerprint so repeated calls do not reuse stale serializer state.
    function toJson(Vm vm, AuctionInvariantRunMetrics memory metrics) internal returns (string memory json) {
        string memory objectKey = string.concat('auctionInvariantRunMetrics-', vm.toString(metrics.runId));

        _serializeRunInfo(vm, objectKey, metrics);
        _serializeAuctionState(vm, objectKey, metrics);
        json = _serializeCounters(vm, objectKey, metrics);
    }

    function _serializeRunInfo(Vm vm, string memory objectKey, AuctionInvariantRunMetrics memory metrics) private {
        vm.serializeString(objectKey, 'testName', metrics.testName);
        vm.serializeString(objectKey, 'invariantName', metrics.invariantName);
        vm.serializeBytes32(objectKey, 'runId', metrics.runId);
        vm.serializeBool(objectKey, 'initialized', metrics.initialized);
        vm.serializeBool(objectKey, 'graduated', metrics.graduated);
        vm.serializeAddress(objectKey, 'auction', metrics.auction);
        vm.serializeUint(objectKey, 'deploymentSeed', metrics.deploymentSeed);
        vm.serializeUint(objectKey, 'blockNumber', metrics.blockNumber);
        vm.serializeUint(objectKey, 'callCount', metrics.callCount);
    }

    function _serializeAuctionState(Vm vm, string memory objectKey, AuctionInvariantRunMetrics memory metrics) private {
        vm.serializeUint(objectKey, 'startBlock', metrics.startBlock);
        vm.serializeUint(objectKey, 'endBlock', metrics.endBlock);
        vm.serializeUint(objectKey, 'claimBlock', metrics.claimBlock);
        vm.serializeUint(objectKey, 'lastCheckpointedBlock', metrics.lastCheckpointedBlock);
        vm.serializeUint(objectKey, 'totalSupply', metrics.totalSupply);
        vm.serializeUint(objectKey, 'numberOfSteps', metrics.numberOfSteps);
        vm.serializeUint(objectKey, 'floorPrice', metrics.floorPrice);
        vm.serializeUint(objectKey, 'tickSpacing', metrics.tickSpacing);
        vm.serializeUint(objectKey, 'clearingPrice', metrics.clearingPrice);
        vm.serializeUint(objectKey, 'totalCleared', metrics.totalCleared);
        vm.serializeUint(objectKey, 'remainingSupply', metrics.remainingSupply);
        vm.serializeUint(objectKey, 'currencyRaised', metrics.currencyRaised);
        vm.serializeUint(objectKey, 'totalCurrencyRaised', metrics.totalCurrencyRaised);
        vm.serializeUint(objectKey, 'bidCount', metrics.bidCount);
    }

    function _serializeCounters(Vm vm, string memory objectKey, AuctionInvariantRunMetrics memory metrics)
        private
        returns (string memory json)
    {
        vm.serializeUint(objectKey, 'cntBidEarlyExited', metrics.cntBidEarlyExited);
        vm.serializeUint(objectKey, 'cntBidExited', metrics.cntBidExited);
        vm.serializeUint(objectKey, 'cntCheckpoints', metrics.cntCheckpoints);
        vm.serializeUint(objectKey, 'cntClearingPriceUpdated', metrics.cntClearingPriceUpdated);
        vm.serializeUint(objectKey, 'cntUntilTickPriceMaxTickPtr', metrics.cntUntilTickPriceMaxTickPtr);
        vm.serializeUint(objectKey, 'cntUntilTickPrice', metrics.cntUntilTickPrice);
        vm.serializeUint(objectKey, 'cntSubmitBidSkippedMaxPrice', metrics.cntSubmitBidSkippedMaxPrice);
        vm.serializeUint(objectKey, 'cntSubmitBidSkippedSoldOut', metrics.cntSubmitBidSkippedSoldOut);
        vm.serializeUint(objectKey, 'cntSubmitBidSkippedAuctionFinished', metrics.cntSubmitBidSkippedAuctionFinished);
        vm.serializeUint(objectKey, 'cntNonGraduatedBidExited', metrics.cntNonGraduatedBidExited);
        vm.serializeUint(objectKey, 'cntClaimTokensBatchNotGraduated', metrics.cntClaimTokensBatchNotGraduated);
        vm.serializeUint(objectKey, 'cntAuctionIsOverError', metrics.cntAuctionIsOverError);
        vm.serializeUint(objectKey, 'cntBidAmountTooSmallError', metrics.cntBidAmountTooSmallError);
        vm.serializeUint(objectKey, 'cntTickPriceNotIncreasingError', metrics.cntTickPriceNotIncreasingError);
        vm.serializeUint(objectKey, 'cntInvalidBidUnableToClearError', metrics.cntInvalidBidUnableToClearError);
        vm.serializeUint(objectKey, 'cntBidMustBeAboveClearingPriceError', metrics.cntBidMustBeAboveClearingPriceError);
        vm.serializeUint(objectKey, 'cntNoBidToEarlyExitError', metrics.cntNoBidToEarlyExitError);
        json = vm.serializeUint(objectKey, 'cntBidAlreadyExitedError', metrics.cntBidAlreadyExitedError);
    }
}
