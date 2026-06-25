// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import {IAuctionStorage} from '../../../src/interfaces/IAuctionStorage.sol';
import {BttBase} from 'btt/BttBase.sol';
import {MockAuctionStorage} from 'btt/mocks/MockAuctionStorage.sol';

import {Currency} from '../../../src/libraries/CurrencyLibrary.sol';
import {MockERC20} from 'btt/mocks/MockERC20.sol';
import {IERC20} from 'forge-std/interfaces/IERC20.sol';

contract SweepUnsoldTokensTest is BttBase {
    function test_WhenAmountEQ0(uint64 _blockNumber) external {
        // it writes sweepUnsoldTokensBlock
        // it does NOT call transfer
        // it emits {TokensSwept}

        vm.roll(_blockNumber);
        address tokensRecipient = makeAddr('tokensRecipient');

        Currency token = Currency.wrap(address(new MockERC20()));

        MockAuctionStorage auctionStorage = new MockAuctionStorage(
            Currency.unwrap(token), address(1), 100e18, tokensRecipient, address(1), 0, address(0)
        );

        assertEq(auctionStorage.sweepUnsoldTokensBlock(), 0);
        assertEq(token.balanceOf(address(auctionStorage)), 0);
        assertEq(token.balanceOf(address(tokensRecipient)), 0);

        vm.expectEmit(true, true, true, true, address(auctionStorage));
        emit IAuctionStorage.TokensSwept(tokensRecipient, 0);

        vm.recordLogs();
        auctionStorage.sweepUnsoldTokens(0);
        assertEq(vm.getRecordedLogs().length, 1);
        assertEq(auctionStorage.sweepUnsoldTokensBlock(), _blockNumber);
        assertEq(token.balanceOf(address(auctionStorage)), 0);
        assertEq(token.balanceOf(address(tokensRecipient)), 0);
    }

    function test_WhenAmountGT0(uint256 _amount, uint64 _blockNumber) external {
        // it writes sweepUnsoldTokensBlock
        // it transfers amount tokens to tokens recipient
        // it emits {TokensSwept}

        vm.roll(_blockNumber);

        address tokensRecipient = makeAddr('tokensRecipient');
        uint256 amount = bound(_amount, 1, type(uint128).max);

        Currency token = Currency.wrap(address(new MockERC20()));

        MockAuctionStorage auctionStorage = new MockAuctionStorage(
            Currency.unwrap(token), address(1), 100e18, tokensRecipient, address(1), 0, address(0)
        );

        deal(Currency.unwrap(token), address(auctionStorage), amount);
        assertEq(token.balanceOf(address(auctionStorage)), amount);
        assertEq(token.balanceOf(address(tokensRecipient)), 0);

        assertEq(auctionStorage.sweepUnsoldTokensBlock(), 0);

        vm.expectEmit(true, true, true, true, Currency.unwrap(token));
        emit IERC20.Transfer(address(auctionStorage), tokensRecipient, amount);

        vm.expectEmit(true, true, true, true, address(auctionStorage));
        emit IAuctionStorage.TokensSwept(tokensRecipient, amount);

        vm.recordLogs();
        auctionStorage.sweepUnsoldTokens(amount);
        assertEq(vm.getRecordedLogs().length, 2);
        assertEq(auctionStorage.sweepUnsoldTokensBlock(), _blockNumber);

        assertEq(token.balanceOf(address(auctionStorage)), 0);
        assertEq(token.balanceOf(address(tokensRecipient)), amount);
    }
}
