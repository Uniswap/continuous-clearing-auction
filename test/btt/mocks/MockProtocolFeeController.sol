// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import {IProtocolFeeController} from 'liquidity-launcher/src/interfaces/IProtocolFeeController.sol';

contract MockProtocolFeeController is IProtocolFeeController {
    address public protocolFeeRecipient;
    uint256 public protocolFeeAmount;

    function setProtocolFeeRecipient(address _recipient) external {
        protocolFeeRecipient = _recipient;
    }

    function setProtocolFeeAmount(uint256 _protocolFeeAmount) external {
        protocolFeeAmount = _protocolFeeAmount;
    }

    function setGlobalProtocolFeePips(uint24) external {}

    function setProtocolFeeBracketsForCurrency(address, ProtocolFeeBracket[] calldata) external {}

    function getProtocolFeeBracketsForCurrency(address) external pure returns (ProtocolFeeBracket[] memory fees) {}

    function getProtocolFeeAmount(address, uint256) external view returns (uint256) {
        return protocolFeeAmount;
    }
}
