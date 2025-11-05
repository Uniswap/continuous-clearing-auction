// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import {Auction} from 'src/Auction.sol';
import {AuctionParameters} from 'src/interfaces/IAuction.sol';
import {AuctionStep} from 'src/libraries/AuctionStepLib.sol';

contract MockAuction is Auction {
    constructor(address _token, uint128 _totalSupply, AuctionParameters memory _parameters)
        Auction(_token, _totalSupply, _parameters)
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
