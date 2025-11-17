// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {Script} from "forge-std/src/Script.sol";

import {IConceroRouter} from "@concero/v2-contracts/contracts/interfaces/IConceroRouter.sol";
import {MessageCodec} from "@concero/v2-contracts/contracts/common/libraries/MessageCodec.sol";

import {ConceroClient} from "@concero/v2-contracts/contracts/ConceroClient/ConceroClient.sol";

contract ConceroRouterMockWithCall is IConceroRouter, Script {
    using MessageCodec for IConceroRouter.MessageRequest;
    using MessageCodec for bytes;

    uint24 public constant PARENT_POOL_CHAIN_SELECTOR = 1000;
    uint24 public s_srcChainSelector = PARENT_POOL_CHAIN_SELECTOR;
    uint256 public constant NONCE = 1;

    address public relayerLib = makeAddr("relayerLib");
    address public validatorLib = makeAddr("validatorLib");

    error InvalidFeeValue();

    function conceroSend(
        IConceroRouter.MessageRequest calldata messageRequest
    ) external payable returns (bytes32 messageId) {
        require(msg.value == _getFee(), InvalidFeeValue());

        bool[] memory validationChecks = new bool[](1);
        validationChecks[0] = true;
        address[] memory validatorLibs = new address[](1);
        validatorLibs[0] = validatorLib;

        bytes memory messageReceipt = messageRequest.toMessageReceiptBytes(
            s_srcChainSelector,
            msg.sender,
            NONCE
        );
        address receiver = readAddress(messageRequest.dstChainData);
        messageId = keccak256(messageReceipt);

        ConceroClient(receiver).conceroReceive(
            messageReceipt,
            validationChecks,
            validatorLibs,
            relayerLib
        );

        return messageId;
    }

    function getMessageFee(
        MessageRequest calldata /** messageRequest */
    ) external view returns (uint256) {
        return _getFee();
    }

    function _getFee() internal pure returns (uint256) {
        return 0.0001 ether;
    }

    function readAddress(bytes memory data) internal pure returns (address) {
        address res;
        assembly {
            res := div(mload(add(add(data, 0x20), 0)), 0x1000000000000000000000000)
        }
        return res;
    }

    function setSrcChainSelector(uint24 srcChainSelector) external {
        s_srcChainSelector = srcChainSelector;
    }
}
