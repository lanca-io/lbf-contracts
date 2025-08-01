// SPDX-License-Identifier: UNLICENSED
/**
 * @title Security Reporting

 * @notice If you discover any security vulnerabilities, please report them responsibly.
 * @contact email: security@concero.io
 */
pragma solidity 0.8.28;

import {
    ConceroTypes,
    IConceroRouter
} from "@concero/v2-contracts/contracts/interfaces/IConceroRouter.sol";

contract MockConceroRouter is IConceroRouter {
    uint256 public constant MESSAGE_FEE = 100;

    uint24 public dstChainSelector;
    bool public shouldFinaliseSrc;
    address public feeToken;
    bytes public message;

    function conceroSend(
        uint24 _dstChainSelector,
        bool _shouldFinaliseSrc,
        address _feeToken,
        ConceroTypes.EvmDstChainData memory /* _dstChainData */,
        bytes calldata _message
    ) external payable returns (bytes32 messageId) {
        dstChainSelector = _dstChainSelector;
        shouldFinaliseSrc = _shouldFinaliseSrc;
        feeToken = _feeToken;
        message = _message;

        return bytes32(uint256(1));
    }

    function getMessageFee(
        uint24 /* dstChainSelector */,
        bool /* shouldFinaliseSrc */,
        address /* feeToken */,
        ConceroTypes.EvmDstChainData memory /* dstChainData */
    ) external pure returns (uint256) {
        return MESSAGE_FEE;
    }
}
