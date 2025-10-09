// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {StdCheats} from 'forge-std/StdCheats.sol';
import {StdCheatsSafe} from 'forge-std/StdCheats.sol';
import {Vm} from 'forge-std/Vm.sol';
import {LibPRNG} from 'solady/utils/LibPRNG.sol';
import {IValidationHook} from 'src/interfaces/IValidationHook.sol';

/// Inspired by https://github.com/ProjectOpenSea/seaport/blob/main/test/foundry/new/helpers/FuzzGeneratorContextLib.sol
struct FuzzGeneratorContext {
    Vm vm;
    LibPRNG.PRNG prng;
    uint256 timestamp;
    address self;
    address caller;
    StdCheats.Account alice;
    StdCheats.Account bob;
    // Validation hook mocks
    IValidationHook validationHook;
    IValidationHook validationHookReverting;
    IValidationHook validationHookWithCustomError;
    IValidationHook validationHookOutOfGas;
}

library FuzzGeneratorContextLib {
    using LibPRNG for LibPRNG.PRNG;

    function empty() internal view returns (FuzzGeneratorContext memory) {
        LibPRNG.PRNG memory prng = LibPRNG.PRNG({state: 0});
        return FuzzGeneratorContext({
            vm: Vm(address(0)),
            prng: prng,
            timestamp: block.timestamp,
            self: address(this),
            caller: address(this),
            alice: StdCheatsSafe.Account({addr: address(0), key: uint256(0)}),
            bob: StdCheatsSafe.Account({addr: address(0), key: uint256(0)}),
            validationHook: IValidationHook(address(0)),
            validationHookReverting: IValidationHook(address(0)),
            validationHookWithCustomError: IValidationHook(address(0)),
            validationHookOutOfGas: IValidationHook(address(0))
        });
    }

    function withTimestamp(FuzzGeneratorContext memory context, uint256 timestamp)
        internal
        pure
        returns (FuzzGeneratorContext memory)
    {
        context.timestamp = timestamp;
        return context;
    }

    function withSelf(FuzzGeneratorContext memory context, address self)
        internal
        pure
        returns (FuzzGeneratorContext memory)
    {
        context.self = self;
        return context;
    }

    function withCaller(FuzzGeneratorContext memory context, address caller)
        internal
        pure
        returns (FuzzGeneratorContext memory)
    {
        context.caller = caller;
        return context;
    }
}
