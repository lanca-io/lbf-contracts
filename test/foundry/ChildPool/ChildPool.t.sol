// SPDX-License-Identifier: UNLICENSED
/* solhint-disable func-name-mixedcase */
pragma solidity 0.8.28;

import {IConceroRouter} from "@concero/v2-contracts/contracts/interfaces/IConceroRouter.sol";
import {MessageCodec} from "@concero/v2-contracts/contracts/common/libraries/MessageCodec.sol";

import {ICommonErrors} from "contracts/common/interfaces/ICommonErrors.sol";
import {IBase} from "contracts/Base/interfaces/IBase.sol";
import {ChildPoolBase} from "./ChildPoolBase.sol";

contract ChildPoolTest is ChildPoolBase {
    using MessageCodec for IConceroRouter.MessageRequest;

    /** -- Test Concero Receive Functions -- */

    function test_handleConceroReceiveUpdateTargetBalance() public {
        uint256 newTargetBalance = 500_000e6;

        bytes memory messagePayload = abi.encode(
            IBase.ConceroMessageType.UPDATE_TARGET_BALANCE,
            abi.encode(newTargetBalance)
        );

        IConceroRouter.MessageRequest memory messageRequest = _buildMessageRequest(
            messagePayload,
            CHILD_POOL_CHAIN_SELECTOR,
            address(childPool)
        );

        vm.prank(conceroRouter);
        childPool.conceroReceive(
            messageRequest.toMessageReceiptBytes(PARENT_POOL_CHAIN_SELECTOR, mockParentPool, NONCE),
            validationChecks,
            validatorLibs,
            relayerLib
        );

        assertEq(childPool.getTargetBalance(), newTargetBalance);
    }

    function test_handleConceroReceiveSnapshot_RevertsFunctionNotImplemented() public {
        bytes memory snapshotData = abi.encode("");
        bytes memory messagePayload = abi.encode(
            IBase.ConceroMessageType.SEND_SNAPSHOT,
            snapshotData
        );

        IConceroRouter.MessageRequest memory messageRequest = _buildMessageRequest(
            messagePayload,
            CHILD_POOL_CHAIN_SELECTOR,
            address(childPool)
        );

        vm.expectRevert(ICommonErrors.FunctionNotImplemented.selector);

        vm.prank(conceroRouter);
        childPool.conceroReceive(
            messageRequest.toMessageReceiptBytes(PARENT_POOL_CHAIN_SELECTOR, mockParentPool, NONCE),
            validationChecks,
            validatorLibs,
            relayerLib
        );
    }

    function test_handleConceroReceiveUpdateTargetBalance_RevertsUnauthorizedSender() public {
        uint256 newTargetBalance = 500_000e6;
        address unauthorizedSender = makeAddr("unauthorizedSender");

        bytes memory messagePayload = abi.encode(
            IBase.ConceroMessageType.UPDATE_TARGET_BALANCE,
            abi.encode(newTargetBalance)
        );

        IConceroRouter.MessageRequest memory messageRequest = _buildMessageRequest(
            messagePayload,
            CHILD_POOL_CHAIN_SELECTOR,
            address(childPool)
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                ICommonErrors.UnauthorizedSender.selector,
                unauthorizedSender,
                makeAddr("parentPool")
            )
        );

        vm.prank(conceroRouter);
        childPool.conceroReceive(
            messageRequest.toMessageReceiptBytes(
                PARENT_POOL_CHAIN_SELECTOR,
                unauthorizedSender,
                NONCE
            ),
            validationChecks,
            validatorLibs,
            relayerLib
        );
    }
}
