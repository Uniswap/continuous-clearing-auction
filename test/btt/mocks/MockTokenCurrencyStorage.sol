// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {TokenCurrencyStorage} from 'twap-auction/TokenCurrencyStorage.sol';

contract MockTokenCurrencyStorage is TokenCurrencyStorage {
    constructor(
        address _token,
        address _currency,
        uint128 _totalSupply,
        address _tokensRecipient,
        address _fundsRecipient
    ) TokenCurrencyStorage(_token, _currency, _totalSupply, _tokensRecipient, _fundsRecipient) {}

    function sweepCurrency(uint256 amount) external {
        _sweepCurrency(amount);
    }

    function sweepUnsoldTokens(uint256 amount) external {
        _sweepUnsoldTokens(amount);
    }
}
