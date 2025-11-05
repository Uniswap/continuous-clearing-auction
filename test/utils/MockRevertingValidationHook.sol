// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IValidationHook} from '../../src/interfaces/IValidationHook.sol';

contract MockRevertingValidationHook is IValidationHook {
    function validate(uint256, uint128, address, address, bytes calldata) external pure {
        revert();
    }
}

contract MockRevertingValidationHookWithCustomError is IValidationHook {
    error CustomError();

    function validate(uint256, uint128, address, address, bytes calldata) external pure {
        revert CustomError();
    }
}

contract MockRevertingValidationHookCustomErrorWithString is IValidationHook {
    error StringError(string reason);

    function validate(uint256, uint128, address, address, bytes calldata) external pure {
        revert StringError('reason');
    }
}

contract MockRevertingValidationHookErrorWithString is IValidationHook {
    function validate(uint256, uint128, address, address, bytes calldata) external pure {
        require(false, 'reason');
    }
}
