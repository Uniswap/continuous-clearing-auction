// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import {BttBase} from 'btt/BttBase.sol';
import {MockCheckpointStorage} from 'btt/mocks/MockCheckpointStorage.sol';
import {Checkpoint} from 'twap-auction/libraries/CheckpointLib.sol';

contract InsertCheckpointTest is BttBase {
    MockCheckpointStorage public mockCheckpointStorage;

    uint256 public constant STORAGE_SLOTS_PER_CHECKPOINT = 4;

    function setUp() external {
        mockCheckpointStorage = new MockCheckpointStorage();
    }

    function test_GivenLastCheckpointedBlockEQ0(Checkpoint memory _checkpoint, uint64 _blockNumber) external {
        // it writes _checkpoints[lastCheckpointedBlock].next = blockNumber
        // it updates checkpoint.prev = lastCheckpointedBlock
        // it updates checkpoint.next = blockNumber
        // it writes $_checkpoints[blockNumber] = checkpoint
        // it writes $lastCheckpointedBlock = blockNumber

        // When it is the first block we do not need to update the previous

        vm.record();
        mockCheckpointStorage.insertCheckpoint(_checkpoint, _blockNumber);
        (, bytes32[] memory writes) = vm.accesses(address(mockCheckpointStorage));

        if (!isCoverage()) {
            // STORAGE_SLOTS_PER_CHECKPOINT writes to update the checkpoint,
            // 1 write to update the last checkpointed block,

            assertEq(writes.length, STORAGE_SLOTS_PER_CHECKPOINT + 1);
        }

        _checkpoint.prev = 0;
        _checkpoint.next = type(uint64).max;

        assertEq(mockCheckpointStorage.latestCheckpoint(), _checkpoint);
        assertEq(mockCheckpointStorage.checkpoints(_blockNumber), _checkpoint);

        assertEq(mockCheckpointStorage.lastCheckpointedBlock(), _blockNumber);
        assertEq(mockCheckpointStorage.clearingPrice(), _checkpoint.clearingPrice);

        // On purpose the first link in the list does not update next (unclear why)
        // assertEq(mockCheckpointStorage.getCheckpoint(0).next, _blockNumber);
    }

    function test_GivenLastCheckpointedBlockNEQ0(
        Checkpoint memory _checkpoint,
        uint64 _blockNumber,
        Checkpoint memory _checkpoint2,
        uint64 _blockNumber2
    ) external {
        // it updates checkpoint.prev = lastCheckpointedBlock
        // it updates checkpoint.next = blockNumber
        // it writes _checkpoints[blockNumber] = checkpoint
        // it writes lastCheckpointedBlock = blockNumber

        // Notes:
        // - It is possible for the "next" to be in the past
        // - It is possible for the "next" to be itself
        // - The $lastCheckpointedBlock might not be the highest block number check pointed

        mockCheckpointStorage.insertCheckpoint(_checkpoint, _blockNumber);

        vm.record();
        mockCheckpointStorage.insertCheckpoint(_checkpoint2, _blockNumber2);
        (, bytes32[] memory writes) = vm.accesses(address(mockCheckpointStorage));

        emit log_named_uint('blockNumber ', _blockNumber);
        emit log_named_uint('blockNumber2', _blockNumber2);

        for (uint64 i = 0; i < writes.length; i++) {
            emit log_named_bytes32('writes', writes[i]);
        }

        bool isFirstZero = _blockNumber == 0;

        if (!isCoverage()) {
            // STORAGE_SLOTS_PER_CHECKPOINT writes to update the checkpoint,
            // 1 write to update next for the last checkpointed
            // 1 write to update the last checkpointed block,

            // Beware that when we are overwriting the last, e.g., _blockNumber == last
            // we end up writing multiple times to the same value.
            assertEq(writes.length, STORAGE_SLOTS_PER_CHECKPOINT + 1 + (isFirstZero ? 0 : 1));
        }

        _checkpoint.prev = 0;
        _checkpoint.next = isFirstZero ? type(uint64).max : _blockNumber2;

        _checkpoint2.prev = _blockNumber;
        _checkpoint2.next = type(uint64).max;

        assertEq(mockCheckpointStorage.latestCheckpoint(), _checkpoint2);
        assertEq(mockCheckpointStorage.checkpoints(_blockNumber2), _checkpoint2);
        assertEq(mockCheckpointStorage.getCheckpoint(_blockNumber2), _checkpoint2);

        assertEq(mockCheckpointStorage.lastCheckpointedBlock(), _blockNumber2);

        if (_blockNumber2 == _blockNumber) {
            assertEq(
                mockCheckpointStorage.getCheckpoint(_blockNumber), mockCheckpointStorage.getCheckpoint(_blockNumber2)
            );
            assertEq(mockCheckpointStorage.checkpoints(_blockNumber), _checkpoint2);
        } else {
            assertEq(mockCheckpointStorage.checkpoints(_blockNumber), _checkpoint);
            assertEq(
                mockCheckpointStorage.getCheckpoint(_blockNumber).next, isFirstZero ? type(uint64).max : _blockNumber2
            );
        }
    }
}
