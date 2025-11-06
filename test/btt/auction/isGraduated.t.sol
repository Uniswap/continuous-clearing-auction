// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import {AuctionFuzzConstructorParams, BttBase} from 'btt/BttBase.sol';

import {MockContinuousClearingAuction} from 'btt/mocks/MockContinuousClearingAuction.sol';
import {IContinuousClearingAuction} from 'continuous-clearing-auction/interfaces/IContinuousClearingAuction.sol';
import {ITokenCurrencyStorage} from 'continuous-clearing-auction/interfaces/ITokenCurrencyStorage.sol';
import {Checkpoint} from 'continuous-clearing-auction/libraries/CheckpointLib.sol';
import {FixedPoint96} from 'continuous-clearing-auction/libraries/FixedPoint96.sol';
import {ERC20Mock} from 'openzeppelin-contracts/contracts/mocks/token/ERC20Mock.sol';

contract IsGraduatedTest is BttBase {
    function test_GivenRaisedIsLTRequired(
        AuctionFuzzConstructorParams memory _params,
        uint128 _requiredCurrencyRaised,
        uint128 _bidAmount
    ) external {
        // it returns false

        alice = makeAddr('alice');

        AuctionFuzzConstructorParams memory mParams = validAuctionConstructorInputs(_params);
        mParams.token = address(new ERC20Mock());
        mParams.parameters.currency = address(0);
        mParams.parameters.validationHook = address(0);
        mParams.totalSupply = uint128(bound(mParams.totalSupply, 1e18, type(uint128).max));
        mParams.parameters.tickSpacing = bound(mParams.parameters.tickSpacing, 2, type(uint24).max) * FixedPoint96.Q96;
        mParams.parameters.floorPrice = bound(mParams.parameters.floorPrice, 1, 100) * mParams.parameters.tickSpacing;

        mParams.parameters.requiredCurrencyRaised = uint128(
            bound(
                _requiredCurrencyRaised, 2, mParams.totalSupply * mParams.parameters.floorPrice / FixedPoint96.Q96 - 1
            )
        );

        MockContinuousClearingAuction auction =
            new MockContinuousClearingAuction(mParams.token, mParams.totalSupply, mParams.parameters);

        ERC20Mock(mParams.token).mint(address(auction), mParams.totalSupply);
        auction.onTokensReceived();

        vm.roll(auction.startBlock());

        uint256 maxPrice = mParams.parameters.floorPrice + mParams.parameters.tickSpacing;
        uint128 bidAmount = uint128(bound(_bidAmount, 1, mParams.parameters.requiredCurrencyRaised - 1));

        vm.deal(address(this), bidAmount);

        auction.submitBid{value: bidAmount}(maxPrice, bidAmount, alice, bytes(''));

        vm.roll(auction.endBlock());

        auction.checkpoint();

        assertFalse(auction.isGraduated(), 'auction is graduated');
    }

    function test_GivenRaisedIsGERequired(
        AuctionFuzzConstructorParams memory _params,
        uint128 _requiredCurrencyRaised,
        uint128 _bidAmount
    ) external {
        // it returns true

        alice = makeAddr('alice');

        AuctionFuzzConstructorParams memory mParams = validAuctionConstructorInputs(_params);
        mParams.token = address(new ERC20Mock());
        mParams.parameters.currency = address(0);
        mParams.parameters.validationHook = address(0);
        mParams.totalSupply = uint128(bound(mParams.totalSupply, 1e18, type(uint128).max));
        mParams.parameters.tickSpacing = bound(mParams.parameters.tickSpacing, 2, type(uint24).max) * FixedPoint96.Q96;
        mParams.parameters.floorPrice = bound(mParams.parameters.floorPrice, 1, 100) * mParams.parameters.tickSpacing;

        mParams.parameters.requiredCurrencyRaised = uint128(
            bound(
                _requiredCurrencyRaised, 1, mParams.totalSupply * mParams.parameters.floorPrice / FixedPoint96.Q96 - 1
            )
        );

        MockContinuousClearingAuction auction =
            new MockContinuousClearingAuction(mParams.token, mParams.totalSupply, mParams.parameters);

        ERC20Mock(mParams.token).mint(address(auction), mParams.totalSupply);
        auction.onTokensReceived();

        vm.roll(auction.startBlock());

        uint256 maxPrice = mParams.parameters.floorPrice + mParams.parameters.tickSpacing;
        uint128 bidAmount = uint128(bound(_bidAmount, mParams.parameters.requiredCurrencyRaised, type(uint128).max));

        vm.deal(address(this), bidAmount);
        auction.submitBid{value: bidAmount}(maxPrice, bidAmount, alice, bytes(''));

        vm.roll(auction.endBlock());

        // @note Relies on the checkpoint, without it we won't be seen as graduated.
        assertFalse(auction.isGraduated(), 'auction is not graduated');

        auction.checkpoint();

        assertTrue(auction.isGraduated(), 'auction is not graduated');
    }
}
