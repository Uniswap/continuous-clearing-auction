// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import {AuctionFuzzConstructorParams, BttBase} from '../BttBase.sol';
import {MockContinuousClearingAuction} from '../mocks/MockContinuousClearingAuction.sol';
import {ERC20Mock} from 'openzeppelin-contracts/contracts/mocks/token/ERC20Mock.sol';
import {IContinuousClearingAuction} from 'src/interfaces/IContinuousClearingAuction.sol';

contract ProcessExitTest is BttBase {
    function test_WhenRefundEqZero(AuctionFuzzConstructorParams memory _params, uint256 _tokensFilled) public {
        // it does not transfer currency to the owner

        AuctionFuzzConstructorParams memory mParams = validAuctionConstructorInputs(_params);
        mParams.token = address(new ERC20Mock());
        mParams.parameters.currency = address(0);

        MockContinuousClearingAuction auction =
            new MockContinuousClearingAuction(mParams.token, mParams.totalSupply, mParams.parameters);

        ERC20Mock(mParams.token).mint(address(auction), mParams.totalSupply);
        auction.onTokensReceived();

        address owner = makeAddr('owner');

        (, uint256 bidId) = auction.createBid(1, owner, 1, 1);

        uint256 balanceBefore = owner.balance;
        auction.processExit(bidId, _tokensFilled, 0);
        uint256 balanceAfter = owner.balance;
        assertEq(balanceAfter, balanceBefore);
    }

    modifier givenRefundGTZero() {
        _;
    }

    function test_WhenCurrencySpentGTBidAmount(
        AuctionFuzzConstructorParams memory _params,
        uint256 _tokensFilled,
        uint256 _amountQ96,
        uint256 _currencySpentQ96
    ) public {
        // it clamps the currency spent to the bid amount

        vm.assume(_amountQ96 > 1 && _amountQ96 < type(uint256).max);
        _currencySpentQ96 = bound(_currencySpentQ96, _amountQ96 + 1, type(uint256).max);

        AuctionFuzzConstructorParams memory mParams = validAuctionConstructorInputs(_params);
        mParams.token = address(new ERC20Mock());
        mParams.parameters.currency = address(0);

        MockContinuousClearingAuction auction =
            new MockContinuousClearingAuction(mParams.token, mParams.totalSupply, mParams.parameters);

        ERC20Mock(mParams.token).mint(address(auction), mParams.totalSupply);
        auction.onTokensReceived();
        address owner = makeAddr('owner');
        (, uint256 bidId) = auction.createBid(_amountQ96, owner, 1, 1);
        vm.deal(address(auction), _amountQ96);

        uint256 balanceBefore = owner.balance;
        vm.expectEmit(true, true, true, true);
        emit IContinuousClearingAuction.BidExited(bidId, owner, _tokensFilled, 0);
        auction.processExit(bidId, _tokensFilled, _currencySpentQ96);
        uint256 balanceAfter = owner.balance;
        assertEq(balanceAfter, balanceBefore);
    }

    function test_WhenRefundGTZero(
        AuctionFuzzConstructorParams memory _params,
        uint256 _tokensFilled,
        uint256 _amountQ96,
        uint256 _currencySpentQ96
    ) public givenRefundGTZero {
        // it transfers the refund to the owner

        vm.assume(_amountQ96 > 1);
        _currencySpentQ96 = bound(_currencySpentQ96, 1, _amountQ96 - 1);
        uint256 refund = (_amountQ96 - _currencySpentQ96) >> 96;
        vm.assume(refund > 0);

        AuctionFuzzConstructorParams memory mParams = validAuctionConstructorInputs(_params);
        mParams.token = address(new ERC20Mock());
        mParams.parameters.currency = address(0);

        MockContinuousClearingAuction auction =
            new MockContinuousClearingAuction(mParams.token, mParams.totalSupply, mParams.parameters);

        ERC20Mock(mParams.token).mint(address(auction), mParams.totalSupply);
        auction.onTokensReceived();
        address owner = makeAddr('owner');
        (, uint256 bidId) = auction.createBid(_amountQ96, owner, 1, 1);
        vm.deal(address(auction), _amountQ96);

        uint256 balanceBefore = owner.balance;
        vm.expectEmit(true, true, true, true);
        emit IContinuousClearingAuction.BidExited(bidId, owner, _tokensFilled, refund);

        vm.record();
        auction.processExit(bidId, _tokensFilled, _currencySpentQ96);

        if (!isCoverage()) {
            (, bytes32[] memory writes) = vm.accesses(address(auction));
            assertEq(writes.length, 2);
        }

        uint256 balanceAfter = owner.balance;
        assertEq(balanceAfter, balanceBefore + refund, 'Balance after should be the balance before plus the refund');
    }
}
