// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {AuctionFuzzConstructorParams, BttBase} from '../BttBase.sol';

import {ContinuousClearingAuction} from 'src/ContinuousClearingAuction.sol';
import {ContinuousClearingAuctionFactory} from 'src/ContinuousClearingAuctionFactory.sol';
import {IContinuousClearingAuctionFactory} from 'src/interfaces/IContinuousClearingAuctionFactory.sol';
import {IDistributionContract} from 'src/interfaces/external/IDistributionContract.sol';
import {ActionConstants} from 'v4-periphery/src/libraries/ActionConstants.sol';

contract InitializeDistributionTest is BttBase {
    ContinuousClearingAuctionFactory internal factory;

    function setUp() public {
        factory = new ContinuousClearingAuctionFactory();
    }

    function test_WhenAmountGTUint128Max(AuctionFuzzConstructorParams memory _params, uint256 _amount)
        external
        setupAuctionConstructorParams(_params)
    {
        // it reverts with {InvalidTokenAmount}
        _amount = uint256(bound(_amount, uint256(type(uint128).max) + 1, type(uint256).max));

        vm.expectRevert(abi.encodeWithSelector(IContinuousClearingAuctionFactory.InvalidTokenAmount.selector, _amount));
        factory.initializeDistribution(address(token), _amount, abi.encode(params), bytes32(0));

        vm.expectRevert(abi.encodeWithSelector(IContinuousClearingAuctionFactory.InvalidTokenAmount.selector, _amount));
        factory.getAuctionAddress(address(token), _amount, abi.encode(params), bytes32(0), address(0));
    }

    modifier whenAmountLEUint128Max(AuctionFuzzConstructorParams memory _params) {
        _params.totalSupply = uint128(bound(_params.totalSupply, 0, type(uint128).max));
        _;
    }

    modifier whenTokensRecipientEQActionConstantsMSG_SENDER(AuctionFuzzConstructorParams memory _params) {
        _params.parameters.tokensRecipient = ActionConstants.MSG_SENDER;
        _;
    }

    function test_WhenFundsRecipientEQActionConstantsMSG_SENDER(
        AuctionFuzzConstructorParams memory _params,
        address _sender
    )
        external
        setupAuctionConstructorParams(_params)
        whenAmountLEUint128Max(_params)
        whenTokensRecipientEQActionConstantsMSG_SENDER(_params)
    {
        // it uses msg.sender as tokensRecipient
        // it uses msg.sender as fundsRecipient
        // it creates an auction
        // it emits {AuctionCreated}
        // it returns the auction

        vm.deal(_sender, 1 ether);
        vm.assume(_sender != address(0));
        vm.assume(_sender != ActionConstants.MSG_SENDER);

        _params.parameters.fundsRecipient = ActionConstants.MSG_SENDER;

        bytes memory auctionParameters = abi.encode(_params.parameters);
        address predictedAddress = factory.getAuctionAddress(
            address(_params.token), _params.totalSupply, auctionParameters, bytes32(0), _sender
        );

        // expect the tokens recipient and funds recipient to be updated to msg.sender
        _params.parameters.tokensRecipient = _sender;
        _params.parameters.fundsRecipient = _sender;
        bytes memory expectedAuctionParameters = abi.encode(_params.parameters);

        vm.expectEmit(false, true, true, true, address(factory));
        emit IContinuousClearingAuctionFactory.AuctionCreated(
            predictedAddress, address(_params.token), _params.totalSupply, expectedAuctionParameters
        );
        vm.prank(_sender);
        IDistributionContract distributionContract =
            factory.initializeDistribution(address(_params.token), _params.totalSupply, auctionParameters, bytes32(0));

        assertEq(address(distributionContract), predictedAddress);
        ContinuousClearingAuction auction = ContinuousClearingAuction(payable(address(distributionContract)));
        assertEq(auction.tokensRecipient(), _sender);
        assertEq(auction.fundsRecipient(), _sender);
    }

    function test_WhenFundsRecipientNEQActionConstantsMSG_SENDER(
        AuctionFuzzConstructorParams memory _params,
        address _sender
    )
        external
        setupAuctionConstructorParams(_params)
        whenAmountLEUint128Max(_params)
        whenTokensRecipientEQActionConstantsMSG_SENDER(_params)
    {
        // it uses msg.sender as tokensRecipient
        // it uses fundsRecipient as fundsRecipient
        // it creates an auction
        // it emits {AuctionCreated}
        // it returns the auction
        vm.assume(_params.parameters.fundsRecipient != ActionConstants.MSG_SENDER);
        vm.deal(_sender, 1 ether);
        vm.assume(_sender != address(0));
        vm.assume(_sender != ActionConstants.MSG_SENDER);

        bytes memory auctionParameters = abi.encode(_params.parameters);
        address predictedAddress = factory.getAuctionAddress(
            address(_params.token), _params.totalSupply, auctionParameters, bytes32(0), _sender
        );

        // expect the tokens recipient to be updated to msg.sender
        _params.parameters.tokensRecipient = _sender;
        bytes memory expectedAuctionParameters = abi.encode(_params.parameters);

        vm.expectEmit(false, true, true, true, address(factory));
        emit IContinuousClearingAuctionFactory.AuctionCreated(
            predictedAddress, address(_params.token), _params.totalSupply, expectedAuctionParameters
        );
        vm.prank(_sender);
        IDistributionContract distributionContract =
            factory.initializeDistribution(address(_params.token), _params.totalSupply, auctionParameters, bytes32(0));

        assertEq(address(distributionContract), predictedAddress);

        ContinuousClearingAuction auction = ContinuousClearingAuction(payable(address(distributionContract)));
        assertEq(auction.tokensRecipient(), _sender);
        assertEq(auction.fundsRecipient(), _params.parameters.fundsRecipient);
    }

    modifier whenTokensRecipientNEQActionConstantsMSG_SENDER(AuctionFuzzConstructorParams memory _params) {
        vm.assume(_params.parameters.tokensRecipient != ActionConstants.MSG_SENDER);
        _;
    }

    function _test_WhenFundsRecipientEQActionConstantsMSG_SENDER2(
        AuctionFuzzConstructorParams memory _params,
        address _sender
    )
        external
        setupAuctionConstructorParams(_params)
        whenAmountLEUint128Max(_params)
        whenTokensRecipientNEQActionConstantsMSG_SENDER(_params)
    {
        // it uses tokensRecipient as tokensRecipient
        // it uses msg.sender as fundsRecipient
        // it creates an auction
        // it emits {AuctionCreated}
        // it returns the auction

        vm.assume(_sender != address(0));
        vm.assume(_sender != ActionConstants.MSG_SENDER);

        _params.parameters.fundsRecipient = ActionConstants.MSG_SENDER;

        bytes memory auctionParameters = abi.encode(_params.parameters);
        address predictedAddress = factory.getAuctionAddress(
            address(_params.token), _params.totalSupply, auctionParameters, bytes32(0), _sender
        );

        // expect the funds recipient to be updated to msg.sender
        _params.parameters.fundsRecipient = _sender;
        bytes memory expectedAuctionParameters = abi.encode(_params.parameters);

        vm.expectEmit(false, true, true, true, address(factory));
        emit IContinuousClearingAuctionFactory.AuctionCreated(
            predictedAddress, address(_params.token), _params.totalSupply, expectedAuctionParameters
        );
        vm.prank(_sender);
        IDistributionContract distributionContract =
            factory.initializeDistribution(address(_params.token), _params.totalSupply, auctionParameters, bytes32(0));

        assertEq(address(distributionContract), predictedAddress);

        ContinuousClearingAuction auction = ContinuousClearingAuction(payable(address(distributionContract)));
        assertEq(auction.tokensRecipient(), _params.parameters.tokensRecipient);
        assertEq(auction.fundsRecipient(), _sender);
    }

    function test_WhenFundsRecipientNEQActionConstantsMSG_SENDER2(
        AuctionFuzzConstructorParams memory _params,
        address _sender
    )
        external
        setupAuctionConstructorParams(_params)
        whenAmountLEUint128Max(_params)
        whenTokensRecipientNEQActionConstantsMSG_SENDER(_params)
    {
        // it uses tokensRecipient as tokensRecipient
        // it uses fundsRecipient as fundsRecipient
        // it creates an auction
        // it emits {AuctionCreated}
        // it returns the auction
        vm.assume(_sender != address(0));
        vm.assume(_sender != ActionConstants.MSG_SENDER);

        vm.assume(_params.parameters.fundsRecipient != ActionConstants.MSG_SENDER);

        bytes memory auctionParameters = abi.encode(_params.parameters);
        address predictedAddress = factory.getAuctionAddress(
            address(_params.token), _params.totalSupply, auctionParameters, bytes32(0), _sender
        );

        bytes memory expectedAuctionParameters = abi.encode(_params.parameters);

        vm.expectEmit(false, true, true, true, address(factory));
        emit IContinuousClearingAuctionFactory.AuctionCreated(
            predictedAddress, address(_params.token), _params.totalSupply, expectedAuctionParameters
        );
        vm.prank(_sender);
        IDistributionContract distributionContract =
            factory.initializeDistribution(address(_params.token), _params.totalSupply, auctionParameters, bytes32(0));

        assertEq(address(distributionContract), predictedAddress);

        ContinuousClearingAuction auction = ContinuousClearingAuction(payable(predictedAddress));
        assertEq(auction.tokensRecipient(), _params.parameters.tokensRecipient);
        assertEq(auction.fundsRecipient(), _params.parameters.fundsRecipient);
    }
}
