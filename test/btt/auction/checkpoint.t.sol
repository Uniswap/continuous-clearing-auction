// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import {AuctionFuzzConstructorParams, BttBase} from '../BttBase.sol';
import {MockContinuousClearingAuction} from '../mocks/MockContinuousClearingAuction.sol';
import {ERC20Mock} from 'openzeppelin-contracts/contracts/mocks/token/ERC20Mock.sol';
import {FixedPointMathLib} from 'solady/utils/FixedPointMathLib.sol';
import {Checkpoint} from 'src/CheckpointStorage.sol';
import {IContinuousClearingAuction} from 'src/interfaces/IContinuousClearingAuction.sol';
import {ConstantsLib} from 'src/libraries/ConstantsLib.sol';

contract CheckpointTest is BttBase {
    function test_WhenAuctionIsNotActive(AuctionFuzzConstructorParams memory _params) public {
        // it reverts with {AuctionNotStarted}

        AuctionFuzzConstructorParams memory mParams = validAuctionConstructorInputs(_params);
        mParams.token = address(new ERC20Mock());

        MockContinuousClearingAuction auction =
            new MockContinuousClearingAuction(mParams.token, mParams.totalSupply, mParams.parameters);

        ERC20Mock(mParams.token).mint(address(auction), mParams.totalSupply);
        auction.onTokensReceived();

        vm.roll(mParams.parameters.startBlock - 1);
        vm.expectRevert(IContinuousClearingAuction.AuctionNotStarted.selector);
        auction.checkpoint();
    }

    modifier givenAuctionIsActive() {
        _;
    }

    function test_WhenBlockNumberGTEndBlock(AuctionFuzzConstructorParams memory _params, uint64 _blockNumber)
        public
        givenAuctionIsActive
    {
        // it returns the final checkpoint

        AuctionFuzzConstructorParams memory mParams = validAuctionConstructorInputs(_params);
        mParams.token = address(new ERC20Mock());
        _blockNumber = uint64(bound(_blockNumber, mParams.parameters.endBlock + 1, type(uint64).max));

        MockContinuousClearingAuction auction =
            new MockContinuousClearingAuction(mParams.token, mParams.totalSupply, mParams.parameters);

        ERC20Mock(mParams.token).mint(address(auction), mParams.totalSupply);
        auction.onTokensReceived();

        vm.roll(_blockNumber);
        Checkpoint memory checkpoint = auction.checkpoint();
        assertEq(checkpoint.cumulativeMps, ConstantsLib.MPS);
    }

    function test_WhenBlockNumberLTEndBlock(AuctionFuzzConstructorParams memory _params) public givenAuctionIsActive {
        // it returns the checkpoint at the block number

        AuctionFuzzConstructorParams memory mParams = validAuctionConstructorInputs(_params);
        mParams.token = address(new ERC20Mock());

        MockContinuousClearingAuction auction =
            new MockContinuousClearingAuction(mParams.token, mParams.totalSupply, mParams.parameters);

        ERC20Mock(mParams.token).mint(address(auction), mParams.totalSupply);
        auction.onTokensReceived();

        vm.roll(mParams.parameters.startBlock);
        Checkpoint memory checkpoint = auction.checkpoint();
        assertEq(checkpoint.cumulativeMps, 0);
    }

    function test_WhenBlockNumberIsSameAsLastCheckpointedBlock(AuctionFuzzConstructorParams memory _params)
        public
        givenAuctionIsActive
    {
        // it does not create a new checkpoint

        AuctionFuzzConstructorParams memory mParams = validAuctionConstructorInputs(_params);
        mParams.token = address(new ERC20Mock());

        MockContinuousClearingAuction auction =
            new MockContinuousClearingAuction(mParams.token, mParams.totalSupply, mParams.parameters);

        ERC20Mock(mParams.token).mint(address(auction), mParams.totalSupply);
        auction.onTokensReceived();

        vm.roll(mParams.parameters.startBlock);
        Checkpoint memory checkpoint = auction.checkpoint();

        vm.record();
        Checkpoint memory checkpoint2 = auction.checkpoint();

        if (!isCoverage()) {
            // Should not write to storage
            (, bytes32[] memory writes) = vm.accesses(address(auction));
            assertEq(writes.length, 0);
        }

        assertEq(checkpoint, checkpoint2);
    }
}
