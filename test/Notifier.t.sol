// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {INotifier} from '../src/interfaces/external/INotifier.sol';
import {ISubscriber} from '../src/interfaces/external/ISubscriber.sol';
import {MockNotifier} from './utils/MockNotifier.sol';
import {MockSubscriber} from './utils/MockSubscriber.sol';
import {Test} from 'forge-std/Test.sol';

contract NotifierTest is Test {
    MockNotifier public notifier;

    ISubscriber[] public subscribers;
    uint64 public constant NOTIFY_BLOCK = 100;
    uint256 public constant PRICE_X192 = 100;
    uint128 public constant TOKEN_AMOUNT = 100;
    uint128 public constant CURRENCY_AMOUNT = 100;

    function setUp() public {
        subscribers = new ISubscriber[](3);
        subscribers[0] = ISubscriber(address(new MockSubscriber()));
        subscribers[1] = ISubscriber(address(new MockSubscriber()));
        subscribers[2] = ISubscriber(address(new MockSubscriber()));
        notifier = new MockNotifier(subscribers, NOTIFY_BLOCK);

        notifier.setPriceX192(PRICE_X192);
        notifier.setTokenAmount(TOKEN_AMOUNT);
        notifier.setCurrencyAmount(CURRENCY_AMOUNT);
    }

    function test_constructor_revertsWhenSubscriberIsZero() public {
        subscribers[0] = ISubscriber(address(0));
        vm.expectRevert(abi.encodeWithSelector(INotifier.SubscriberIsZero.selector));
        new MockNotifier(subscribers, NOTIFY_BLOCK);
    }

    function test_notifyAllSubscribers_succeeds() public {
        vm.roll(NOTIFY_BLOCK);
        for (uint256 i = 0; i < subscribers.length; i++) {
            vm.expectEmit(true, true, true, true, address(subscribers[i]));
            emit ISubscriber.InitialPriceSet(PRICE_X192, TOKEN_AMOUNT, CURRENCY_AMOUNT);
        }
        notifier.notify();
    }

    function test_notifyBeforeNotifyBlock_reverts() public {
        vm.roll(NOTIFY_BLOCK - 1);
        vm.expectRevert(abi.encodeWithSelector(INotifier.CannotNotifyYet.selector));
        notifier.notify();
    }
}
