// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ValueX7} from '../libraries/ValueX7Lib.sol';

interface IAuctionStorage {
    /// @notice The currency raised as of the last checkpoint in Q96 representation, scaled up by X7
    /// @dev Most use cases will want to use `currencyRaised()` instead
    function currencyRaisedQ96_X7() external view returns (ValueX7);

    /// @notice Get the currency raised at the last checkpointed block
    /// @dev This may be less than the balance of this contract if there are outstanding refunds for bidders
    /// @dev Relies on the latest checkpoint which may be out of date
    /// @return The currency raised
    function currencyRaised() external view returns (uint256);

    /// @notice The sum of demand in ticks above the clearing price
    function sumCurrencyDemandAboveClearingQ96() external view returns (uint256);

    /// @notice The total currency raised as of the last checkpoint in Q96 representation, scaled up by X7
    function totalClearedQ96_X7() external view returns (ValueX7);

    /// @notice The total tokens cleared as of the last checkpoint in uint256 representation
    /// @dev Loses precision from dividing into uint256 form
    function totalCleared() external view returns (uint256);
}
