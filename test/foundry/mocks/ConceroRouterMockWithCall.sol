// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {IConceroRouter} from "@concero/v2-contracts/contracts/interfaces/IConceroRouter.sol";

import {ConceroClient} from "@concero/v2-contracts/contracts/ConceroClient/ConceroClient.sol";

contract ConceroRouterMockWithCall is IConceroRouter {
    uint24 public constant PARENT_POOL_CHAIN_SELECTOR = 1000;

    error InvalidFeeValue();

    function conceroSend(
        MessageRequest calldata messageRequest
    ) external payable returns (bytes32 messageId) {
        require(msg.value == _getFee(), InvalidFeeValue());

        messageId = keccak256(abi.encode(messageRequest));

        // ConceroClient(dstChainData.receiver).conceroReceive(
        //     messageId,
        //     PARENT_POOL_CHAIN_SELECTOR,
        //     abi.encode(msg.sender),
        //     message
        // );

        return messageId;
    }

    function getMessageFee(MessageRequest calldata messageRequest) external view returns (uint256) {
        return _getFee();
    }

    function _getFee() internal pure returns (uint256) {
        return 0.0001 ether;
    }
}
