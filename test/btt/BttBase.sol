// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import {Test} from 'forge-std/Test.sol';
import {VmSafe} from 'forge-std/Vm.sol';

import {Bid} from 'twap-auction/BidStorage.sol';

import {AuctionParameters} from 'twap-auction/interfaces/IAuction.sol';

// Chore: move to a shared place
import {CompactStep, CompactStepLib, Step} from 'test/btt/libraries/auctionStepLib/StepUtils.sol';
import {ConstantsLib} from 'twap-auction/libraries/ConstantsLib.sol';

import {AuctionBaseTest} from 'test/utils/AuctionBaseTest.sol';
import {AuctionStep} from 'twap-auction/libraries/AuctionStepLib.sol';

struct AuctionFuzzConstructorParams {
    address token;
    uint128 totalSupply;
    AuctionParameters parameters;
    Step[] steps;
}

contract BttBase is AuctionBaseTest {
    function isCoverage() internal view returns (bool) {
        return vm.isContext(VmSafe.ForgeContext.Coverage);
    }

    modifier setupAuctionConstructorParams(AuctionFuzzConstructorParams memory _params) {
        _params = validAuctionConstructorInputs(_params);
        _;
    }

    // Temporary clone of function within auction base test
    function _boundPriceParams(AuctionParameters memory _parameters) private pure {
        // Bound tick spacing to be less than or equal to floor price
        _parameters.tickSpacing = _bound(_parameters.tickSpacing, 2, type(uint96).max);
        // Bound tick spacing and floor price to reasonable values
        _parameters.floorPrice = _bound(_parameters.floorPrice, _parameters.tickSpacing, type(uint128).max);
        // Round down floor price to the closest multiple of tick spacing
        _parameters.floorPrice = helper__roundPriceDownToTickSpacing(_parameters.floorPrice, _parameters.tickSpacing);
        // Ensure floor price is non-zero
        vm.assume(_parameters.floorPrice != 0);
    }

    function validAuctionConstructorInputs(AuctionFuzzConstructorParams memory _params)
        internal
        returns (AuctionFuzzConstructorParams memory)
    {
        // Bound to be sensible values
        vm.assume(_params.totalSupply > 0);
        vm.assume(_params.token != _params.parameters.currency);
        vm.assume(_params.token != address(0));
        vm.assume(_params.parameters.fundsRecipient != address(0));
        vm.assume(_params.parameters.tokensRecipient != address(0));

        (bytes memory auctionStepsData, uint256 numberOfBlocks,) = generateAuctionSteps(_params.steps);

        _params.parameters.startBlock =
            uint64(bound(_params.parameters.startBlock, 1, type(uint64).max - numberOfBlocks - 2));
        _params.parameters.endBlock = _params.parameters.startBlock + uint64(numberOfBlocks);
        _params.parameters.claimBlock = _params.parameters.endBlock + 1;
        _params.parameters.auctionStepsData = auctionStepsData;

        emit log('bound price');

        _boundPriceParams(_params.parameters);

        emit log('validAuctionConstructorInputs ending');

        return _params;
    }

    /**
     * Take in a randomly generated sequencer of auction steps and generate a compatible sequence
     * - The sum of all of the mps generated should be equal to the total mps
     * - If the randomly generated sequence becomes too large, or falls short, we fill it with a single step which mades up the difference
     */
    function generateAuctionSteps(Step[] memory _steps) internal pure returns (bytes memory, uint256, Step[] memory) {
        vm.assume(_steps.length > 0);

        uint256 totalMps = 0;
        uint256 numberOfSteps = 0;
        while (totalMps < ConstantsLib.MPS && numberOfSteps < _steps.length) {
            _steps[numberOfSteps].mps = uint24(bound(_steps[numberOfSteps].mps, 0, ConstantsLib.MPS - totalMps));
            _steps[numberOfSteps].blockDelta = uint40(bound(_steps[numberOfSteps].blockDelta, 1, type(uint16).max));

            // If the next step would exceed the total mps, or we are on the last step, set the mps and block delta to the remaining mps and 1
            // Otherwise if we are out of fuzz steps, we need to just make up the difference
            if (
                totalMps + (_steps[numberOfSteps].mps * _steps[numberOfSteps].blockDelta) > ConstantsLib.MPS
                    || numberOfSteps == _steps.length - 1
            ) {
                _steps[numberOfSteps].mps = uint24(ConstantsLib.MPS - totalMps);
                _steps[numberOfSteps].blockDelta = 1;
            }
            totalMps += _steps[numberOfSteps].mps * _steps[numberOfSteps].blockDelta;
            numberOfSteps++;
        }
        assertEq(totalMps, ConstantsLib.MPS, 'totalMps');

        // Encode the steps into the compact step format
        // Calculate the total number of blocks to inform the fuzzed endBlock Values
        CompactStep[] memory steps = new CompactStep[](numberOfSteps);
        uint256 numberOfBlocks = 0;
        for (uint256 i = 0; i < numberOfSteps; i++) {
            steps[i] = CompactStepLib.create(uint24(_steps[i].mps), uint40(_steps[i].blockDelta));
            numberOfBlocks += _steps[i].blockDelta;
        }

        bytes memory auctionStepsData = CompactStepLib.pack(steps);

        return (auctionStepsData, numberOfBlocks, _steps);
    }

    function assertEq(Bid memory _bid, Bid memory _bid2) internal pure {
        assertEq(_bid.startBlock, _bid2.startBlock, 'startBlock');
        assertEq(_bid.startCumulativeMps, _bid2.startCumulativeMps, 'startCumulativeMps');
        assertEq(_bid.exitedBlock, _bid2.exitedBlock, 'exitedBlock');
        assertEq(_bid.maxPrice, _bid2.maxPrice, 'maxPrice');
        assertEq(_bid.owner, _bid2.owner, 'owner');
        assertEq(_bid.amountQ96, _bid2.amountQ96, 'amountQ96');
        assertEq(_bid.tokensFilled, _bid2.tokensFilled, 'tokensFilled');
    }

    function assertEq(AuctionStep memory _step, AuctionStep memory _step2) internal pure {
        assertEq(_step.startBlock, _step2.startBlock, 'startBlock');
        assertEq(_step.endBlock, _step2.endBlock, 'endBlock');
        assertEq(_step.mps, _step2.mps, 'mps');
    }
}
