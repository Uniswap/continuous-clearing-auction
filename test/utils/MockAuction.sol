// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Auction} from '../../src/Auction.sol';
import {AuctionParameters} from '../../src/Auction.sol';
import {Bid} from '../../src/BidStorage.sol';
import {Checkpoint} from '../../src/CheckpointStorage.sol';
import {ValueX7} from '../../src/libraries/ValueX7Lib.sol';

contract MockAuction is Auction {
    constructor(address _token, uint128 _totalSupply, AuctionParameters memory _parameters)
        Auction(_token, _totalSupply, _parameters)
    {}

    /// @notice Wrapper around internal function for testing
    function iterateOverTicksAndFindClearingPrice(Checkpoint memory checkpoint) external returns (uint256) {
        return _iterateOverTicksAndFindClearingPrice(checkpoint);
    }

    /// @notice Wrapper around internal function for testing
    function sellTokensAtClearingPrice(Checkpoint memory checkpoint, uint24 deltaMps)
        external
        returns (Checkpoint memory)
    {
        return _sellTokensAtClearingPrice(checkpoint, deltaMps);
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
    function uncheckedUpdateTickDemand(uint256 price, uint256 currencyDemandQ96) external {
        _updateTickDemand(price, currencyDemandQ96);
    }

    /// @notice Set the $sumDemandAboveClearing
    function uncheckedSetSumDemandAboveClearing(uint256 currencyDemandQ96) external {
        $sumCurrencyDemandAboveClearingQ96 = currencyDemandQ96;
    }

    function uncheckedAddToSumDemandAboveClearing(uint256 currencyDemandQ96) external {
        $sumCurrencyDemandAboveClearingQ96 += currencyDemandQ96;
    }
}
