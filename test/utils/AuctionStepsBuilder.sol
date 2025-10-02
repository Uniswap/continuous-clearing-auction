// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ConstantsLib} from '../../src/libraries/ConstantsLib.sol';

library AuctionStepsBuilder {
    function init() internal pure returns (bytes memory) {
        return new bytes(0);
    }

    function splitEvenlyAmongSteps(uint40 numberOfSteps) internal pure returns (bytes memory) {
        uint24 mps = uint24(ConstantsLib.MPS / numberOfSteps);
        return abi.encodePacked(mps, numberOfSteps);
    }

    function addStep(bytes memory steps, uint24 mps, uint40 blockDelta) internal pure returns (bytes memory) {
        return abi.encodePacked(steps, abi.encodePacked(mps, blockDelta));
    }
}
