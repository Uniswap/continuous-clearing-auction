// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import {BttBase} from 'btt/BttBase.sol';
import {AuctionStepLib} from 'twap-auction/libraries/AuctionStepLib.sol';

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

contract GetTest is BttBase {
    function test_WhenReadingBeyondTheDataLength() external {
        // it reverts with {InvalidOffset}
        assertEq(isCoverage(), true, 'To be implemented');
    }

    modifier whenReadingWithinTheDataLength() {
        _;
    }

    function test_WhenNotReadingAMultipleOf8Bytes() external whenReadingWithinTheDataLength {
        // it reverts with {InvalidOffset}
        assertEq(isCoverage(), true, 'To be implemented');
    }

    function test_WhenReadingAMultipleOf8Bytes(Step[16] memory _steps, uint256 _offset)
        external
        whenReadingWithinTheDataLength
    {
        // it returns mps and block delta

        CompactStep[] memory steps = new CompactStep[](_steps.length);
        for (uint256 i = 0; i < _steps.length; i++) {
            steps[i] = CompactStepLib.create(_steps[i].mps, _steps[i].blockDelta);
        }

        bytes memory data = CompactStepLib.pack(steps);

        uint256 index = bound(_offset, 0, steps.length - 1);
        uint256 offset = index * 8;

        (uint24 mps, uint40 blockDelta) = AuctionStepLib.get(data, offset);
        assertEq(mps, _steps[index].mps);
        assertEq(blockDelta, _steps[index].blockDelta);
    }
}
