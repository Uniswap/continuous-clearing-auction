// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Bid} from '../../src/BidStorage.sol';
import {Checkpoint} from '../../src/CheckpointStorage.sol';
import {ContinuousClearingAuction} from '../../src/ContinuousClearingAuction.sol';
import {AuctionParameters} from '../../src/ContinuousClearingAuction.sol';

import {FixedPoint96} from '../../src/libraries/FixedPoint96.sol';
import {ValueX7} from '../../src/libraries/ValueX7Lib.sol';
import {ValueX7Lib} from '../../src/libraries/ValueX7Lib.sol';

contract MockContinuousClearingAuction is ContinuousClearingAuction {
    using ValueX7Lib for *;

    constructor(address _token, uint128 _totalSupply, AuctionParameters memory _parameters)
        ContinuousClearingAuction(_token, _totalSupply, _parameters)
    {}

    /// @notice The number of tokens that can be swept from the auction
    /// @dev Only use this function if you know the auction is graduated
    function sweepableTokens() external view returns (uint256) {
        return TOTAL_SUPPLY_Q96.scaleUpToX7().sub($totalClearedQ96_X7).divUint256(FixedPoint96.Q96).scaleDownToUint256();
    }

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
