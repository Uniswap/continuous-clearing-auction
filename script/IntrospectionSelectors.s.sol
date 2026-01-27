// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IValidationHook} from '../src/interfaces/IValidationHook.sol';
import {IBaseERC1155ValidationHook} from '../src/periphery/validationHooks/BaseERC1155ValidationHook.sol';
import {IGatedERC1155ValidationHook} from '../src/periphery/validationHooks/GatedERC1155ValidationHook.sol';
import {IValidationHookIntrospection} from '../src/periphery/validationHooks/ValidationHookIntrospection.sol';
import {IERC165} from '@openzeppelin/contracts/utils/introspection/IERC165.sol';
import {console} from 'forge-std/console.sol';

contract IntrospectionSelectors {
    function run() public {
        console.log('IERC165');
        console.logBytes4(type(IERC165).interfaceId);
        console.log('IValidationHook');
        console.logBytes4(type(IValidationHook).interfaceId);
        console.log('IBaseERC1155ValidationHook');
        console.logBytes4(type(IBaseERC1155ValidationHook).interfaceId);
        console.log('IGatedERC1155ValidationHook');
        console.logBytes4(type(IGatedERC1155ValidationHook).interfaceId);
    }
}
