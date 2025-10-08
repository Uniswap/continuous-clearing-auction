// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {FuzzGeneratorContext, FuzzGeneratorContextLib} from './FuzzGeneratorContextLib.sol';

struct FuzzTestContext {
    // selector of the action to be performed
    bytes4 _action;
    /**
     * @dev A struct containing the context for the FuzzGenerator. This is used
     *      upstream to generate the order state and is included here for use
     *      and reference throughout the rest of the lifecycle.
     */
    FuzzGeneratorContext generatorContext;
}

library FuzzTestContextLib {
    using FuzzGeneratorContextLib for FuzzGeneratorContext;

    function empty() internal pure returns (FuzzTestContext memory) {
        return FuzzTestContext({_action: bytes4(0), generatorContext: FuzzGeneratorContextLib.empty()});
    }
}
