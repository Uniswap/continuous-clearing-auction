// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IAuctionStorage} from './interfaces/IAuctionStorage.sol';
import {ConstantsLib} from './libraries/ConstantsLib.sol';
import {FixedPoint96} from './libraries/FixedPoint96.sol';
import {ValueX7} from './libraries/ValueX7Lib.sol';
import {FixedPointMathLib} from 'solady/utils/FixedPointMathLib.sol';

/// @title AuctionStorage
/// @notice Abstract contract for managing auction storage
abstract contract AuctionStorage is IAuctionStorage {
    /// @notice The total currency raised in the auction in Q96 representation, scaled up by X7
    ValueX7 internal $currencyRaisedQ96X7;
    /// @notice The total tokens sold in the auction so far, in Q96 representation, scaled up by X7
    ValueX7 internal $totalClearedQ96X7;
    /// @notice The sum of currency demand in ticks above the clearing price
    /// @dev This will increase every time a new bid is submitted, and decrease when bids are outbid.
    uint256 internal $sumCurrencyDemandAboveClearingQ96;
    /// @notice The most up to date clearing price, set on each call to `checkpoint`
    /// @dev This can be incremented manually by calling `forceIterateOverTicks`
    uint256 internal $clearingPrice;

    /// @notice Whether the TOTAL_SUPPLY of tokens has been received
    bool internal $_tokensReceived;

    /// @inheritdoc IAuctionStorage
    function currencyRaised() public view returns (uint256) {
        return (ValueX7.unwrap($currencyRaisedQ96X7) / FixedPoint96.Q96) / ConstantsLib.MPS;
    }

    /// @inheritdoc IAuctionStorage
    function currencyRaisedQ96X7() public view returns (ValueX7) {
        return $currencyRaisedQ96X7;
    }

    /// @inheritdoc IAuctionStorage
    function sumCurrencyDemandAboveClearingQ96() public view returns (uint256) {
        return $sumCurrencyDemandAboveClearingQ96;
    }

    /// @inheritdoc IAuctionStorage
    function totalClearedQ96X7() public view returns (ValueX7) {
        return $totalClearedQ96X7;
    }

    /// @inheritdoc IAuctionStorage
    function totalCleared() public view returns (uint256) {
        return (ValueX7.unwrap($totalClearedQ96X7) / FixedPoint96.Q96) / ConstantsLib.MPS;
    }
}
