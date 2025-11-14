// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {IConceroRouter} from "@concero/v2-contracts/contracts/interfaces/IConceroRouter.sol";

contract ConceroRouterMock is IConceroRouter {
    error InvalidFeeValue();

    function conceroSend(
        MessageRequest calldata messageRequest
    ) external payable returns (bytes32 messageId) {
        require(msg.value == _getFee(), InvalidFeeValue());

        return keccak256(abi.encode(messageRequest));
    }

    function getMessageFee(
        MessageRequest calldata /** messageRequest */
    ) external view returns (uint256) {
        return _getFee();
    }

    function _getFee() internal pure returns (uint256) {
        return 0.0001 ether;
    }
}
