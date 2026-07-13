// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import {IAuctionStorage} from '../../../src/interfaces/IAuctionStorage.sol';
import {BttBase} from 'btt/BttBase.sol';
import {MockAuctionStorage} from 'btt/mocks/MockAuctionStorage.sol';

import {MockERC20} from 'btt/mocks/MockERC20.sol';

import {Currency} from '../../../src/libraries/CurrencyLibrary.sol';
import {Vm, VmSafe} from 'forge-std/Vm.sol';
import {IERC20} from 'forge-std/interfaces/IERC20.sol';

contract SweepCurrencyTest is BttBase {
    function test_WhenAmountEQ0(bool _isNativeCurrency, uint64 _blockNumber) external {
        // it writes sweepCurrencyBlock
        // it does not transfer currency to funds recipient
        // it emits {CurrencySwept}

        vm.roll(_blockNumber);
        address fundsRecipient = makeAddr('fundsRecipient');

        address currency = _isNativeCurrency ? address(0) : address(new MockERC20());

        MockAuctionStorage auctionStorage =
            new MockAuctionStorage(address(1), currency, 100e18, address(1), fundsRecipient, 0, address(0));

        assertEq(auctionStorage.sweepCurrencyBlock(), 0);

        assertEq(Currency.wrap(currency).balanceOf(address(auctionStorage)), 0);
        assertEq(Currency.wrap(currency).balanceOf(address(fundsRecipient)), 0);

        if (_isNativeCurrency) {
            vm.startStateDiffRecording();
        } else {
            // Expect 0 calls to transfer
            vm.expectCall(currency, abi.encodeWithSelector(IERC20.transfer.selector, address(fundsRecipient), 0), 0);
        }

        auctionStorage.sweepCurrency(0);

        if (_isNativeCurrency) {
            Vm.AccountAccess[] memory accountAccesses = vm.stopAndReturnStateDiff();

            uint256 callCountToFundsRecipient = 0;
            for (uint256 i = 0; i < accountAccesses.length; i++) {
                if (
                    accountAccesses[i].account == fundsRecipient
                        && accountAccesses[i].kind == VmSafe.AccountAccessKind.Call
                ) {
                    callCountToFundsRecipient++;
                }
            }
            assertEq(callCountToFundsRecipient, 0);
        }

        assertEq(auctionStorage.sweepCurrencyBlock(), _blockNumber, 'sweepCurrencyBlock is not equal to block number');
        assertEq(Currency.wrap(currency).balanceOf(address(auctionStorage)), 0);
        assertEq(Currency.wrap(currency).balanceOf(address(fundsRecipient)), 0);
    }

    function test_WhenAmountGT0(bool _isNativeCurrency, uint256 _amount, uint64 _blockNumber) external {
        // it writes sweepCurrencyBlock
        // it transfers amount currency to funds recipient
        // it emits {CurrencySwept}

        vm.roll(_blockNumber);
        address fundsRecipient = makeAddr('fundsRecipient');

        address currency = _isNativeCurrency ? address(0) : address(new MockERC20());

        MockAuctionStorage auctionStorage =
            new MockAuctionStorage(address(1), currency, 100e18, address(1), fundsRecipient, 0, address(0));

        uint256 amount = bound(_amount, 1, type(uint128).max);

        if (_isNativeCurrency) {
            vm.deal(address(auctionStorage), amount);
        } else {
            deal(address(currency), address(auctionStorage), amount);
        }

        assertEq(Currency.wrap(currency).balanceOf(address(auctionStorage)), amount);
        assertEq(Currency.wrap(currency).balanceOf(address(fundsRecipient)), 0);

        if (!_isNativeCurrency) {
            vm.expectEmit(true, true, true, true, address(currency));
            emit IERC20.Transfer(address(auctionStorage), fundsRecipient, amount);
        }

        vm.expectEmit(true, true, true, true, address(auctionStorage));
        emit IAuctionStorage.CurrencySwept(fundsRecipient, amount);

        if (_isNativeCurrency) {
            vm.startStateDiffRecording();
        }
        auctionStorage.sweepCurrency(amount);

        if (_isNativeCurrency) {
            Vm.AccountAccess[] memory accountAccesses = vm.stopAndReturnStateDiff();

            uint256 callCountToFundsRecipient = 0;
            for (uint256 i = 0; i < accountAccesses.length; i++) {
                if (
                    accountAccesses[i].account == fundsRecipient
                        && accountAccesses[i].kind == VmSafe.AccountAccessKind.Call
                ) {
                    callCountToFundsRecipient++;
                }
            }
            assertEq(callCountToFundsRecipient, 1);
        }

        assertEq(auctionStorage.sweepCurrencyBlock(), _blockNumber, 'sweepCurrencyBlock is not equal to block number');
        assertEq(Currency.wrap(currency).balanceOf(address(auctionStorage)), 0);
        assertEq(Currency.wrap(currency).balanceOf(address(fundsRecipient)), amount);
    }
}
