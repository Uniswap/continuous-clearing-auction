// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {AuctionFuzzConstructorParams, BttBase} from '../BttBase.sol';

import {ERC20Mock} from 'openzeppelin-contracts/contracts/mocks/token/ERC20Mock.sol';
import {Auction} from 'src/Auction.sol';
import {IAuction} from 'src/interfaces/IAuction.sol';

contract OnTokensReceivedTest is BttBase {
    function test_Given_tokensReceivedEQTrue(AuctionFuzzConstructorParams memory _params)
        external
        setupAuctionConstructorParams(_params)
    {
        // it returns early

        // Use the mock ERC20 contract for the token
        _params.token = address(new ERC20Mock());

        Auction auction = new Auction(_params.token, _params.totalSupply, _params.parameters);

        ERC20Mock(_params.token).mint(address(auction), _params.totalSupply);
        auction.onTokensReceived();

        vm.record();
        auction.onTokensReceived();
        (bytes32[] memory reads, bytes32[] memory writes) = vm.accesses(address(auction));

        // If short circuiting we expect 0 writes
        // And one read for the $_tokensReceived variable
        if (!isCoverage()) {
            assertEq(writes.length, 0);
            assertEq(reads.length, 1);
        }
    }

    modifier given_tokensReceivedNEQTrue() {
        _;
    }

    function test_WhenTOKENBalanceLTTOTAL_SUPPLY(AuctionFuzzConstructorParams memory _params, uint256 _amountToSend)
        external
        setupAuctionConstructorParams(_params)
        given_tokensReceivedNEQTrue
    {
        // it reverts with {InvalidTokenAmountReceived}

        _params.token = address(new ERC20Mock());
        Auction auction = new Auction(_params.token, _params.totalSupply, _params.parameters);

        uint256 amountToSend = bound(_amountToSend, 0, _params.totalSupply - 1);

        ERC20Mock(_params.token).mint(address(auction), amountToSend);
        vm.expectRevert(IAuction.InvalidTokenAmountReceived.selector);
        auction.onTokensReceived();
    }

    function test_WhenTOKENBalanceGETOTAL_SUPPLY(AuctionFuzzConstructorParams memory _params, uint256 _amountToSend)
        external
        setupAuctionConstructorParams(_params)
        given_tokensReceivedNEQTrue
    {
        // it writes _tokensReceived
        // it emits {TokensReceived}

        _params.token = address(new ERC20Mock());
        Auction auction = new Auction(_params.token, _params.totalSupply, _params.parameters);

        uint256 amountToSend = bound(_amountToSend, _params.totalSupply, type(uint256).max);

        ERC20Mock(_params.token).mint(address(auction), amountToSend);

        vm.expectEmit(true, true, true, true, address(auction));
        emit IAuction.TokensReceived(_params.totalSupply);
        vm.record();
        auction.onTokensReceived();
        (bytes32[] memory reads, bytes32[] memory writes) = vm.accesses(address(auction));

        // We expect a read for the $_tokensReceived variable
        if (!isCoverage()) {
            assertEq(writes.length, 1);
            // 1 read of tokensReceived
            // 1 read of TOKEN.balanceOf(address(this))
            // 1 read when writing
            assertEq(reads.length, 3);

            bool tokensReceived = uint256(vm.load(address(auction), writes[0])) & 1 == 1;
            assertEq(tokensReceived, true);
        }
    }
}
