// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

// TODO: move to a shared place

struct Step {
    uint24 mps;
    uint40 blockDelta;
}

type CompactStep is uint64;

library CompactStepLib {
    function create(uint24 _mps, uint40 _blockDelta) internal pure returns (CompactStep) {
        return CompactStep.wrap(uint64((uint256(_mps) << 40 | uint256(_blockDelta))));
    }

    function pack(CompactStep[] memory _steps) internal pure returns (bytes memory) {
        bytes memory data = new bytes(_steps.length * 8);
        for (uint256 i = 0; i < _steps.length; i++) {
            uint256 val = uint256(CompactStep.unwrap(_steps[i])) << 192;
            assembly {
                mstore(add(data, add(0x20, mul(i, 8))), val)
            }
        }
        return data;
    }
}
