// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {AuctionFuzzConstructorParams, BttBase} from 'btt/BttBase.sol';
import {MockContinuousClearingAuction} from 'btt/mocks/MockContinuousClearingAuction.sol';
import {IERC165} from 'openzeppelin-contracts/contracts/interfaces/IERC165.sol';
import {ILBPInitializer} from 'src/interfaces/external/ILBPInitializer.sol';

contract SupportsInterfaceTest is BttBase {
    function test_WhenInterfaceIsSupported(AuctionFuzzConstructorParams memory _params) external {
        // it returns true

        AuctionFuzzConstructorParams memory mParams = validAuctionConstructorInputs(_params);

        MockContinuousClearingAuction auction =
            new MockContinuousClearingAuction(mParams.token, mParams.totalSupply, mParams.parameters);

        assertTrue(auction.supportsInterface(type(ILBPInitializer).interfaceId));
        assertTrue(auction.supportsInterface(type(IERC165).interfaceId));
    }

    function test_WhenInterfaceIsNotSupported(AuctionFuzzConstructorParams memory _params, bytes4 _interfaceId)
        external
    {
        // it returns false

        vm.assume(_interfaceId != type(ILBPInitializer).interfaceId && _interfaceId != type(IERC165).interfaceId);

        AuctionFuzzConstructorParams memory mParams = validAuctionConstructorInputs(_params);

        MockContinuousClearingAuction auction =
            new MockContinuousClearingAuction(mParams.token, mParams.totalSupply, mParams.parameters);

        assertFalse(auction.supportsInterface(_interfaceId));
    }
}
