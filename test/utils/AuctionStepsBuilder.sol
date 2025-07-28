// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

library AuctionStepsBuilder {
    function init() internal pure returns (bytes memory) {
        return new bytes(0);
    }

    function addStep(bytes memory steps, uint24 mps, uint40 blockDelta) internal pure returns (bytes memory) {
        return abi.encodePacked(steps, abi.encodePacked(mps, blockDelta));
    }
}
