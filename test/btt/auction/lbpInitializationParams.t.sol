// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {AuctionFuzzConstructorParams, BttBase} from 'btt/BttBase.sol';
import {MockContinuousClearingAuction} from 'btt/mocks/MockContinuousClearingAuction.sol';
import {MockProtocolFeeController} from 'btt/mocks/MockProtocolFeeController.sol';
import {LBPInitializationParams} from 'liquidity-launcher/src/interfaces/ILBPInitializer.sol';
import {ERC20Mock} from 'openzeppelin-contracts/contracts/mocks/token/ERC20Mock.sol';
import {IAuctionStorage} from 'src/interfaces/IAuctionStorage.sol';
import {IContinuousClearingAuction} from 'src/interfaces/IContinuousClearingAuction.sol';

contract LBPInitializationParamsTest is BttBase {
    function test_WhenAuctionIsNotFinalized(AuctionFuzzConstructorParams memory _params, uint64 _blockNumber) external {
        // it reverts with {AuctionIsNotFinalized}
        AuctionFuzzConstructorParams memory mParams = validAuctionConstructorInputs(_params);
        mParams.token = address(new ERC20Mock());

        MockContinuousClearingAuction auction =
            new MockContinuousClearingAuction(mParams.token, mParams.totalSupply, mParams.parameters, address(0));

        ERC20Mock(mParams.token).mint(address(auction), requiredTokenDeposit(mParams));
        auction.onTokensReceived();

        _blockNumber = uint64(bound(_blockNumber, mParams.parameters.startBlock, mParams.parameters.endBlock - 1));
        vm.roll(_blockNumber);
        auction.checkpoint();

        vm.expectRevert(IContinuousClearingAuction.AuctionIsNotFinalized.selector);
        auction.lbpInitializationParams();
    }

    modifier givenAuctionIsFinalized() {
        _;
    }

    function test_WhenAuctionIsFinalizedButNotGraduated(AuctionFuzzConstructorParams memory _params)
        external
        givenAuctionIsFinalized
    {
        // it reverts with {NotGraduated}
        AuctionFuzzConstructorParams memory mParams = validAuctionConstructorInputs(_params);
        mParams.token = address(new ERC20Mock());
        mParams.parameters.requiredCurrencyRaised = 1;

        MockContinuousClearingAuction auction =
            new MockContinuousClearingAuction(mParams.token, mParams.totalSupply, mParams.parameters, address(0));

        ERC20Mock(mParams.token).mint(address(auction), requiredTokenDeposit(mParams));
        auction.onTokensReceived();

        vm.roll(auction.endBlock());
        auction.checkpoint();

        assertFalse(auction.isGraduated(), 'auction is graduated');
        vm.expectRevert(IAuctionStorage.NotGraduated.selector);
        auction.lbpInitializationParams();
    }

    function test_WhenAuctionIsFinalized(AuctionFuzzConstructorParams memory _params) external givenAuctionIsFinalized {
        // it returns the correct initialization params
        AuctionFuzzConstructorParams memory mParams = validAuctionConstructorInputs(_params);
        mParams.token = address(new ERC20Mock());
        mParams.parameters.requiredCurrencyRaised = 0;

        MockContinuousClearingAuction auction =
            new MockContinuousClearingAuction(mParams.token, mParams.totalSupply, mParams.parameters, address(0));

        ERC20Mock(mParams.token).mint(address(auction), requiredTokenDeposit(mParams));
        auction.onTokensReceived();

        vm.roll(auction.endBlock());
        auction.checkpoint();

        LBPInitializationParams memory params = auction.lbpInitializationParams();
        assertEq(params.initialPriceX96, auction.clearingPrice());
        assertEq(params.tokensSold, auction.totalCleared());
        assertEq(params.currencyRaised, auction.currencyRaised());
    }

    function test_WhenAuctionIsFinalizedAndProtocolFeeIsSet_ReturnsNetCurrencyRaised(
        AuctionFuzzConstructorParams memory _params,
        uint128 _bidAmount,
        uint256 _protocolFeeAmount
    ) external givenAuctionIsFinalized {
        // it returns currency raised after subtracting protocol fees
        vm.deal(address(this), type(uint256).max);
        vm.assume(_bidAmount > 0);

        AuctionFuzzConstructorParams memory mParams = validAuctionConstructorInputs(_params);
        mParams.token = address(new ERC20Mock());
        mParams.parameters.currency = address(0);
        mParams.parameters.validationHook = address(0);
        mParams.parameters.requiredCurrencyRaised = 0;

        MockProtocolFeeController protocolFeeController = new MockProtocolFeeController();
        MockContinuousClearingAuction auction = new MockContinuousClearingAuction(
            mParams.token, mParams.totalSupply, mParams.parameters, address(protocolFeeController)
        );

        ERC20Mock(mParams.token).mint(address(auction), requiredTokenDeposit(mParams));
        auction.onTokensReceived();

        vm.roll(mParams.parameters.startBlock);
        uint256 maxPrice = mParams.parameters.floorPrice + mParams.parameters.tickSpacing;
        auction.submitBid{value: _bidAmount}(maxPrice, _bidAmount, address(this), bytes(''));

        vm.roll(auction.endBlock());
        auction.checkpoint();

        uint256 grossCurrencyRaised = auction.currencyRaised();
        _protocolFeeAmount = bound(_protocolFeeAmount, 0, grossCurrencyRaised);
        protocolFeeController.setProtocolFeeAmount(_protocolFeeAmount);

        LBPInitializationParams memory params = auction.lbpInitializationParams();
        assertEq(params.initialPriceX96, auction.clearingPrice());
        assertEq(params.tokensSold, auction.totalCleared());
        assertEq(params.currencyRaised, grossCurrencyRaised - _protocolFeeAmount);
        assertEq(auction.currencyRaised(), grossCurrencyRaised);
    }
}
