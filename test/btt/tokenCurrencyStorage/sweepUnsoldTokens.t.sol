// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import {BttBase} from 'btt/BttBase.sol';
import {MockTokenCurrencyStorage} from 'btt/mocks/MockTokenCurrencyStorage.sol';
import {ITokenCurrencyStorage} from 'twap-auction/interfaces/ITokenCurrencyStorage.sol';

import {MockERC20} from 'btt/mocks/MockERC20.sol';
import {IERC20} from 'forge-std/interfaces/IERC20.sol';
import {Currency} from 'twap-auction/libraries/CurrencyLibrary.sol';

contract SweepUnsoldTokensTest is BttBase {
    function test_WhenAmountEQ0(uint256 _blockNumber) external {
        // it writes sweepUnsoldTokensBlock
        // it does NOT call transfer
        // it emits {TokensSwept}

        vm.roll(_blockNumber);
        address tokensRecipient = makeAddr('tokensRecipient');

        Currency token = Currency.wrap(address(new MockERC20()));

        MockTokenCurrencyStorage tokenCurrencyStorage =
            new MockTokenCurrencyStorage(Currency.unwrap(token), address(1), 100e18, tokensRecipient, address(1), 0);

        assertEq(tokenCurrencyStorage.sweepUnsoldTokensBlock(), 0);
        assertEq(token.balanceOf(address(tokenCurrencyStorage)), 0);
        assertEq(token.balanceOf(address(tokensRecipient)), 0);

        vm.expectEmit(true, true, true, true, address(tokenCurrencyStorage));
        emit ITokenCurrencyStorage.TokensSwept(tokensRecipient, 0);

        vm.recordLogs();
        tokenCurrencyStorage.sweepUnsoldTokens(0);
        assertEq(vm.getRecordedLogs().length, 1);
        assertEq(tokenCurrencyStorage.sweepUnsoldTokensBlock(), _blockNumber);
        assertEq(token.balanceOf(address(tokenCurrencyStorage)), 0);
        assertEq(token.balanceOf(address(tokensRecipient)), 0);
    }

    function test_WhenAmountGT0(uint256 _amount, uint256 _blockNumber) external {
        // it writes sweepUnsoldTokensBlock
        // it transfers amount tokens to tokens recipient
        // it emits {TokensSwept}

        vm.roll(_blockNumber);

        address tokensRecipient = makeAddr('tokensRecipient');
        uint256 amount = bound(_amount, 1, type(uint128).max);

        Currency token = Currency.wrap(address(new MockERC20()));

        MockTokenCurrencyStorage tokenCurrencyStorage =
            new MockTokenCurrencyStorage(Currency.unwrap(token), address(1), 100e18, tokensRecipient, address(1), 0);

        deal(Currency.unwrap(token), address(tokenCurrencyStorage), amount);
        assertEq(token.balanceOf(address(tokenCurrencyStorage)), amount);
        assertEq(token.balanceOf(address(tokensRecipient)), 0);

        assertEq(tokenCurrencyStorage.sweepUnsoldTokensBlock(), 0);

        vm.expectEmit(true, true, true, true, Currency.unwrap(token));
        emit IERC20.Transfer(address(tokenCurrencyStorage), tokensRecipient, amount);

        vm.expectEmit(true, true, true, true, address(tokenCurrencyStorage));
        emit ITokenCurrencyStorage.TokensSwept(tokensRecipient, amount);

        vm.recordLogs();
        tokenCurrencyStorage.sweepUnsoldTokens(amount);
        assertEq(vm.getRecordedLogs().length, 2);
        assertEq(tokenCurrencyStorage.sweepUnsoldTokensBlock(), _blockNumber);

        assertEq(token.balanceOf(address(tokenCurrencyStorage)), 0);
        assertEq(token.balanceOf(address(tokensRecipient)), amount);
    }
}
