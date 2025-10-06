// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Auction} from '../../src/Auction.sol';
import {AuctionParameters} from '../../src/Auction.sol';
import {Bid} from '../../src/BidStorage.sol';
import {Checkpoint} from '../../src/CheckpointStorage.sol';
import {SupplyLib, SupplyRolloverMultiplier} from '../../src/libraries/SupplyLib.sol';
import {ValueX7} from '../../src/libraries/ValueX7Lib.sol';

import {ValueX7} from '../../src/libraries/ValueX7Lib.sol';
import {ValueX7X7} from '../../src/libraries/ValueX7X7Lib.sol';

contract MockAuction is Auction {
    constructor(address _token, uint128 _totalSupply, AuctionParameters memory _parameters)
        Auction(_token, _totalSupply, _parameters)
    {}

    function getTotalCurrencyRaisedAtFloorX7X7() external view returns (ValueX7X7) {
        return TOTAL_CURRENCY_RAISED_AT_FLOOR_X7_X7;
    }

    /// @notice Wrapper around internal function for testing
    function calculateNewClearingPrice(
        uint256 tickLowerPrice,
        ValueX7 sumCurrencyDemandAboveClearingX7,
        ValueX7X7 remainingCurrencyRaisedX7X7,
        uint24 remainingMpsInAuction
    ) external view returns (uint256) {
        return _calculateNewClearingPrice(
            tickLowerPrice, sumCurrencyDemandAboveClearingX7, remainingCurrencyRaisedX7X7, remainingMpsInAuction
        );
    }

    /// @notice Wrapper around internal function for testing
    function iterateOverTicksAndFindClearingPrice(Checkpoint memory checkpoint) external returns (uint256) {
        return _iterateOverTicksAndFindClearingPrice(checkpoint);
    }

    /// @notice Wrapper around internal function for testing
    function unpackSupplyRolloverMultiplier()
        external
        view
        returns (bool isSet, uint24 remainingMps, ValueX7X7 remainingCurrencyRaisedX7X7)
    {
        return SupplyLib.unpack($_supplyRolloverMultiplier);
    }

    /// @notice Wrapper around internal function for testing
    function setSupplyRolloverMultiplier(bool set, uint24 remainingMps, ValueX7X7 remainingSupplyX7X7) external {
        $_supplyRolloverMultiplier = SupplyLib.packSupplyRolloverMultiplier(set, remainingMps, remainingSupplyX7X7);
    }

    /// @notice Helper function to insert a checkpoint
    function insertCheckpoint(Checkpoint memory _checkpoint, uint64 blockNumber) external {
        _insertCheckpoint(_checkpoint, blockNumber);
    }

    function getBid(uint256 bidId) external view returns (Bid memory) {
        return _getBid(bidId);
    }

    /// @notice Add a bid to storage without updating the tick demand or $sumDemandAboveClearing
    function uncheckedCreateBid(uint128 amount, address owner, uint256 maxPrice, uint24 startCumulativeMps)
        external
        returns (Bid memory, uint256)
    {
        return _createBid(amount, owner, maxPrice, startCumulativeMps);
    }

    function uncheckedInitializeTickIfNeeded(uint256 prevPrice, uint256 price) external {
        _initializeTickIfNeeded(prevPrice, price);
    }

    function uncheckedSetNextActiveTickPrice(uint256 price) external {
        $nextActiveTickPrice = price;
    }

    /// @notice Update the tick demand
    function uncheckedUpdateTickDemand(uint256 price, ValueX7 currencyDemandX7) external {
        _updateTickDemand(price, currencyDemandX7);
    }

    /// @notice Set the $sumDemandAboveClearing
    function uncheckedSetSumDemandAboveClearing(ValueX7 currencyDemandX7) external {
        $sumCurrencyDemandAboveClearingX7 = currencyDemandX7;
    }

    function uncheckedAddToSumDemandAboveClearing(ValueX7 currencyDemandX7) external {
        $sumCurrencyDemandAboveClearingX7 = $sumCurrencyDemandAboveClearingX7.add(currencyDemandX7);
    }
}
