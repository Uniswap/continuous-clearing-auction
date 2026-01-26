// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {BlockNumberish} from 'blocknumberish/src/BlockNumberish.sol';
import {TokenCurrencyStorage} from 'continuous-clearing-auction/TokenCurrencyStorage.sol';
import {Currency} from 'continuous-clearing-auction/libraries/CurrencyLibrary.sol';

contract MockTokenCurrencyStorage is TokenCurrencyStorage, BlockNumberish {
    constructor(
        address _token,
        address _currency,
        uint128 _totalSupply,
        address _tokensRecipient,
        address _fundsRecipient,
        uint128 _requiredCurrencyRaised
    )
        TokenCurrencyStorage(
            _token, _currency, _totalSupply, _tokensRecipient, _fundsRecipient, _requiredCurrencyRaised
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
