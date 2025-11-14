// SPDX-License-Identifier: UNLICENSED
/**
 * @title Security Reporting

 * @notice If you discover any security vulnerabilities, please report them responsibly.
 * @contact email: security@concero.io
 */
pragma solidity 0.8.28;

import {IConceroRouter} from "@concero/v2-contracts/contracts/interfaces/IConceroRouter.sol";

contract MockConceroRouter is IConceroRouter {
    uint256 public constant MESSAGE_FEE = 100;

    // uint24 public dstChainSelector;
    // bool public shouldFinaliseSrc;
    // address public feeToken;
    // bytes public message;

    function conceroSend(
        MessageRequest calldata messageRequest
    ) external payable returns (bytes32 messageId) {
        // dstChainSelector = _dstChainSelector;
        // shouldFinaliseSrc = _shouldFinaliseSrc;
        // feeToken = _feeToken;
        // message = _message;

        return bytes32(uint256(1));
    }

    function getMessageFee(MessageRequest calldata messageRequest) external view returns (uint256) {
        return MESSAGE_FEE;
    }
}
