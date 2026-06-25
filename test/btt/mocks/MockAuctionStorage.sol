// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {BlockNumberish} from 'blocknumberish/src/BlockNumberish.sol';
import {AuctionStorage} from '../../../src/AuctionStorage.sol';
import {Currency} from '../../../src/libraries/CurrencyLibrary.sol';

contract MockAuctionStorage is AuctionStorage, BlockNumberish {
    constructor(
        address _token,
        address _currency,
        uint128 _totalSupply,
        address _tokensRecipient,
        address _fundsRecipient,
        uint128 _requiredCurrencyRaised,
        address _protocolFeeController
    )
        AuctionStorage(
            _token,
            _currency,
            _totalSupply,
            _tokensRecipient,
            _fundsRecipient,
            _requiredCurrencyRaised,
            _protocolFeeController
        )
        BlockNumberish()
    {}

    function sweepCurrency(uint256 amount) external {
        _sweepCurrency(_getBlockNumberish(), amount);
    }

    function sweepUnsoldTokens(uint256 amount) external {
        _sweepUnsoldTokens(_getBlockNumberish(), amount);
    }

    // Mock getters

    function token() external view returns (address) {
        return address(TOKEN);
    }

    function currency() external view returns (address) {
        return Currency.unwrap(CURRENCY);
    }

    function totalSupply() external view returns (uint128) {
        return TOTAL_SUPPLY;
    }

    function tokensRecipient() external view returns (address) {
        return TOKENS_RECIPIENT;
    }

    function fundsRecipient() external view returns (address) {
        return FUNDS_RECIPIENT;
    }
}
