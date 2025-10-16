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

contract AuctionStepWrapper {
    constructor() {}

    function parse(bytes8 data) public pure returns (uint24 mps, uint40 blockDelta) {
        (mps, blockDelta) = AuctionStepLib.parse(data);
    }

    function get(bytes memory data, uint256 offset) public pure returns (uint24 mps, uint40 blockDelta) {
        (mps, blockDelta) = AuctionStepLib.get(data, offset);
    }

}

contract GetTest is BttBase {
    CompactStep[] $steps;
    bytes $data;

    AuctionStepWrapper auctionStep;

    function setUp() public {
        auctionStep = new AuctionStepWrapper();
    }

    function _setupSteps(Step[] memory _steps) private {
        CompactStep[] memory steps = new CompactStep[](_steps.length);
        for (uint256 i = 0; i < _steps.length; i++) {
            steps[i] = CompactStepLib.create(_steps[i].mps, _steps[i].blockDelta);
        }
        $steps = steps;
        $data = CompactStepLib.pack(steps);
    }

    modifier setupSteps(Step[] memory _steps) {
        _setupSteps(_steps);
        _;
    }

    modifier setupStepsFixedLength(Step[16] memory _steps) {
        Step[] memory steps = new Step[](_steps.length);
        for (uint256 i = 0; i < _steps.length; i++) {
            steps[i] = _steps[i];
        }
        _setupSteps(steps);
        _;
    }

    function test_WhenReadingBeyondTheDataLength(Step[] memory _steps, uint256 _offset) external setupSteps(_steps) {
        // it reverts with {InvalidOffset}
        bytes memory data = $data;
        CompactStep[] memory steps = $steps;

        _offset = bound(_offset, data.length, type(uint256).max);

        uint256 dataLength = data.length;
        _offset = bound(_offset, dataLength, dataLength + 8);
        vm.expectRevert(abi.encodeWithSelector(AuctionStepLib.AuctionStepLib__InvalidOffsetTooLarge.selector));
        auctionStep.get(data, _offset);
    }

    modifier whenReadingWithinTheDataLength() {
        _;
    }

    function test_WhenNotReadingAMultipleOf8Bytes(Step[] memory _steps, uint256 _offset) external setupSteps(_steps) {
        // it reverts with {InvalidOffset}
        vm.assume(_steps.length > 0);

        bytes memory data = $data;
        CompactStep[] memory steps = $steps;

        uint256 index = bound(_offset, 0, steps.length - 1);
        uint256 offset = index * 8 + 1;
        vm.expectRevert(abi.encodeWithSelector(AuctionStepLib.AuctionStepLib__InvalidOffsetNotAtStepBoundary.selector));
        auctionStep.get(data, offset);
    }

    function test_WhenReadingAMultipleOf8Bytes(Step[16] memory _steps, uint256 _offset)
        external
        setupStepsFixedLength(_steps)
        whenReadingWithinTheDataLength
    {
        // it returns mps and block delta
        bytes memory data = $data;
        CompactStep[] memory steps = $steps;

        uint256 index = bound(_offset, 0, steps.length - 1);
        uint256 offset = index * 8;

        (uint24 mps, uint40 blockDelta) = AuctionStepLib.get(data, offset);
        assertEq(mps, _steps[index].mps);
        assertEq(blockDelta, _steps[index].blockDelta);
    }
}
