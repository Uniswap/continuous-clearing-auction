// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import {ContinuousClearingAuction} from 'src/ContinuousClearingAuction.sol';
import {AuctionParameters} from 'src/interfaces/IContinuousClearingAuction.sol';
import {AuctionStep} from 'src/libraries/StepLib.sol';

contract MockContinuousClearingAuction is ContinuousClearingAuction {
    constructor(address _token, uint128 _totalSupply, AuctionParameters memory _parameters)
        ContinuousClearingAuction(_token, _totalSupply, _parameters)
    {}

    /// @notice Mock wrapper around internal function for testing
    function advanceToStartOfCurrentStep(uint64 _blockNumber)
        external
        returns (AuctionStep memory step, uint24 deltaMps)
    {
        return _advanceToStartOfCurrentStep(_blockNumber, $lastCheckpointedBlock);
    }

    function modifier_onlyAfterAuctionIsOver() external onlyAfterAuctionIsOver {}

    function modifier_onlyAfterClaimBlock() external onlyAfterClaimBlock {}

    function modifier_onlyActiveAuction() external onlyActiveAuction {}
}
