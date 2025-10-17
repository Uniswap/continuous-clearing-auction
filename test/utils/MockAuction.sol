// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Auction} from '../../src/Auction.sol';
import {AuctionParameters} from '../../src/Auction.sol';
import {Bid} from '../../src/BidStorage.sol';
import {Checkpoint} from '../../src/CheckpointStorage.sol';
import {ValueX7} from '../../src/libraries/ValueX7Lib.sol';
import {ClearingPrice} from '../../src/Auction.sol';

contract MockAuction is Auction {
    constructor(address _token, uint128 _totalSupply, AuctionParameters memory _parameters)
        Auction(_token, _totalSupply, _parameters)
    {}

    /// @notice Wrapper around internal function for testing
    function iterateOverTicksAndFindClearingPrice(Checkpoint memory _checkpoint) external returns (ClearingPrice memory) {
        return _iterateOverTicksAndFindClearingPrice(_checkpoint);
    }

    /// @notice Helper function to insert a checkpoint
    function insertCheckpoint(Checkpoint memory _checkpoint, uint64 _blockNumber) external {
        _insertCheckpoint(_checkpoint, _blockNumber);
    }

    function getBid(uint256 _bidId) external view returns (Bid memory) {
        return _getBid(_bidId);
    }

    /// @notice Add a bid to storage without updating the tick demand or $sumDemandAboveClearing
    function uncheckedCreateBid(uint128 _amount, address _owner, uint256 _maxPrice, uint24 _startCumulativeMps)
        external
        returns (Bid memory, uint256)
    {
        return _createBid(_amount, _owner, _maxPrice, _startCumulativeMps);
    }

    function uncheckedInitializeTickIfNeeded(uint256 _prevPrice, uint256 _price) external {
        _initializeTickIfNeeded(_prevPrice, _price);
    }

    function uncheckedSetNextActiveTickPrice(uint256 _price) external {
        $nextActiveTickPrice = _price;
    }

    /// @notice Update the tick demand
    function uncheckedUpdateTickDemand(uint256 _price, uint256 _currencyDemandQ96) external {
        _updateTickDemand(_price, _currencyDemandQ96);
    }

    /// @notice Set the $sumDemandAboveClearing
    function uncheckedSetSumDemandAboveClearing(uint256 _currencyDemandQ96) external {
        $sumCurrencyDemandAboveClearingQ96 = _currencyDemandQ96;
    }

    function uncheckedAddToSumDemandAboveClearing(uint256 _currencyDemandQ96) external {
        $sumCurrencyDemandAboveClearingQ96 += _currencyDemandQ96;
    }
}
