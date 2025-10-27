// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ConstantsLib} from '../../src/libraries/ConstantsLib.sol';

library AuctionStepsBuilder {
    function init() internal pure returns (bytes memory) {
        return new bytes(0);
    }

    function splitEvenlyAmongSteps(uint40 numberOfSteps) internal pure returns (bytes memory) {
        uint24 mpsPerBlock = uint24(ConstantsLib.MPS / numberOfSteps);
        return abi.encodePacked(mpsPerBlock, numberOfSteps);
    }

    function addStep(bytes memory steps, uint24 mpsPerBlock, uint40 blockDelta) internal pure returns (bytes memory) {
        return abi.encodePacked(steps, abi.encodePacked(mpsPerBlock, blockDelta));
    }
}
