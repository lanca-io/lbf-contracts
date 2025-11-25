// SPDX-License-Identifier: UNLICENSED
/* solhint-disable func-name-mixedcase */
pragma solidity 0.8.28;

import {IConceroRouter} from "@concero/v2-contracts/contracts/interfaces/IConceroRouter.sol";
import {MessageCodec} from "@concero/v2-contracts/contracts/common/libraries/MessageCodec.sol";
import {BridgeCodec} from "contracts/common/libraries/BridgeCodec.sol";
import {ICommonErrors} from "contracts/common/interfaces/ICommonErrors.sol";
import {IBase} from "contracts/Base/interfaces/IBase.sol";
import {ChildPoolBase} from "./ChildPoolBase.sol";

contract ChildPoolTest is ChildPoolBase {
    using MessageCodec for IConceroRouter.MessageRequest;

    /** -- Test Concero Receive Functions -- */

    function testFuzz_handleConceroReceiveUpdateTargetBalance(uint256 newTargetBalance) public {
        IConceroRouter.MessageRequest memory messageRequest = _buildMessageRequest(
            BridgeCodec.encodeUpdateTargetBalanceData(newTargetBalance, USDC_TOKEN_DECIMALS),
            CHILD_POOL_CHAIN_SELECTOR,
            address(s_childPool)
        );

        vm.prank(s_conceroRouter);
        s_childPool.conceroReceive(
            messageRequest.toMessageReceiptBytes(
                PARENT_POOL_CHAIN_SELECTOR,
                s_mockParentPool,
                NONCE
            ),
            s_validationChecks,
            s_validatorLibs,
            s_relayerLib
        );

        assertEq(s_childPool.getTargetBalance(), newTargetBalance);
    }

    function test_handleConceroReceiveSnapshot_RevertsFunctionNotImplemented() public {
        IConceroRouter.MessageRequest memory messageRequest = _buildMessageRequest(
            BridgeCodec.encodeChildPoolSnapshotData(1, 1, 1, 1, 1, 1, 1, 1, 1, 1),
            CHILD_POOL_CHAIN_SELECTOR,
            address(s_childPool)
        );

        vm.expectRevert(ICommonErrors.FunctionNotImplemented.selector);

        vm.prank(s_conceroRouter);
        s_childPool.conceroReceive(
            messageRequest.toMessageReceiptBytes(
                PARENT_POOL_CHAIN_SELECTOR,
                s_mockParentPool,
                NONCE
            ),
            s_validationChecks,
            s_validatorLibs,
            s_relayerLib
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
            address(s_childPool)
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                ICommonErrors.UnauthorizedSender.selector,
                unauthorizedSender,
                makeAddr("parentPool")
            )
        );

        vm.prank(s_conceroRouter);
        s_childPool.conceroReceive(
            messageRequest.toMessageReceiptBytes(
                PARENT_POOL_CHAIN_SELECTOR,
                unauthorizedSender,
                NONCE
            ),
            s_validationChecks,
            s_validatorLibs,
            s_relayerLib
        );
    }
}
