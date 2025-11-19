// SPDX-License-Identifier: UNLICENSED
/* solhint-disable func-name-mixedcase */
pragma solidity 0.8.28;

import {IConceroRouter} from "@concero/v2-contracts/contracts/interfaces/IConceroRouter.sol";
import {MessageCodec} from "@concero/v2-contracts/contracts/common/libraries/MessageCodec.sol";
import {BridgeCodec} from "contracts/common/libraries/BridgeCodec.sol";
import {IBase} from "contracts/Base/interfaces/IBase.sol";
import {ParentPool} from "contracts/ParentPool/ParentPool.sol";
import {IParentPool} from "contracts/ParentPool/interfaces/IParentPool.sol";
import {ICommonErrors} from "contracts/common/interfaces/ICommonErrors.sol";
import {ParentPoolBase} from "../ParentPool/ParentPoolBase.sol";

contract ReceiveSnapshot is ParentPoolBase {
    using MessageCodec for IConceroRouter.MessageRequest;

    function setUp() public override {
        super.setUp();
        vm.warp(NOW_TIMESTAMP);
    }

    function test_ReceiveSnapshot_Success() public {
        uint256 activeBalance = 100e6;
        uint256 inflow = 200e6;
        uint256 outflow = 300e6;
        uint256 iouTotalSent = 400e6;
        uint256 iouTotalReceived = 500e6;
        uint256 iouTotalSupply = 600e6;

        IBase.LiqTokenDailyFlow memory dailyFlow = IBase.LiqTokenDailyFlow({
            inflow: inflow,
            outflow: outflow
        });

        IParentPool.ChildPoolSnapshot memory snapshot = IParentPool.ChildPoolSnapshot({
            balance: activeBalance,
            dailyFlow: dailyFlow,
            iouTotalSent: iouTotalSent,
            iouTotalReceived: iouTotalReceived,
            iouTotalSupply: iouTotalSupply,
            timestamp: uint32(block.timestamp),
            //todo: fill it
            totalLiqTokenSent: 0,
            totalLiqTokenReceived: 0
        });

        IConceroRouter.MessageRequest memory messageRequest = _buildMessageRequest(
            BridgeCodec.encodeChildPoolSnapshotData(
                activeBalance,
                dailyFlow.inflow,
                dailyFlow.outflow,
                iouTotalSent,
                iouTotalReceived,
                iouTotalSupply,
                uint32(block.timestamp),
                0,
                0
            ),
            PARENT_POOL_CHAIN_SELECTOR,
            address(s_parentPool)
        );

        vm.prank(s_conceroRouter);
        s_parentPool.conceroReceive(
            messageRequest.toMessageReceiptBytes(
                childPoolChainSelector_1,
                address(s_childPool_1),
                NONCE
            ),
            s_validationChecks,
            s_validatorLibs,
            s_relayerLib
        );

        IParentPool.ChildPoolSnapshot memory receivedSnapshot = s_parentPool
            .exposed_getChildPoolSnapshot(childPoolChainSelector_1);

        assertEq(receivedSnapshot.balance, activeBalance);
        assertEq(receivedSnapshot.dailyFlow.inflow, inflow);
        assertEq(receivedSnapshot.dailyFlow.outflow, outflow);
        assertEq(receivedSnapshot.iouTotalSent, iouTotalSent);
        assertEq(receivedSnapshot.iouTotalReceived, iouTotalReceived);
        assertEq(receivedSnapshot.iouTotalSupply, iouTotalSupply);
        assertEq(receivedSnapshot.timestamp, uint32(block.timestamp));
    }

    function test_ReceiveSnapshot_CannotBeUsedTwice() public {
        _setQueuesLength(0, 0);
        _enterDepositQueue(s_user, _addDecimals(100));

        _fillChildPoolSnapshots();

        s_parentPool.exposed_setChildPoolSnapshot(
            childPoolChainSelector_1,
            _getChildPoolSnapshot(_addDecimals(1_500), 0, 0)
        );
        IParentPool.ChildPoolSnapshot memory snapshot = s_parentPool.exposed_getChildPoolSnapshot(
            childPoolChainSelector_1
        );
        assertEq(snapshot.timestamp, NOW_TIMESTAMP);

        assertTrue(s_parentPool.isReadyToTriggerDepositWithdrawProcess());

        _triggerDepositWithdrawProcess();

        snapshot = s_parentPool.exposed_getChildPoolSnapshot(childPoolChainSelector_1);

        // The snapshot timestamp should be 0 because it cannot be used twice
        assertEq(snapshot.timestamp, 0);
        assertFalse(s_parentPool.isReadyToTriggerDepositWithdrawProcess());
    }

    function test_ReceiveSnapshot_CannotBeReceivedFromInvalidSender() public {
        IParentPool.ChildPoolSnapshot memory snapshot = s_parentPool.exposed_getChildPoolSnapshot(
            childPoolChainSelector_1
        );

        address invalidSender = address(0x123);

        IConceroRouter.MessageRequest memory messageRequest = _buildMessageRequest(
            abi.encode(IBase.ConceroMessageType.SEND_SNAPSHOT, abi.encode(snapshot)),
            PARENT_POOL_CHAIN_SELECTOR,
            address(s_parentPool)
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                ICommonErrors.UnauthorizedSender.selector,
                invalidSender,
                s_childPool_1
            )
        );

        vm.prank(s_conceroRouter);
        s_parentPool.conceroReceive(
            messageRequest.toMessageReceiptBytes(childPoolChainSelector_1, invalidSender, NONCE),
            s_validationChecks,
            s_validatorLibs,
            s_relayerLib
        );
    }

    function test_ReceiveSnapshot_CannotBeUsedWithExpiredTimestamp() public {
        _setQueuesLength(0, 0);
        _enterDepositQueue(s_user, _addDecimals(100));

        _fillChildPoolSnapshots();

        vm.warp(NOW_TIMESTAMP + 10 minutes + 1);

        vm.expectRevert(IParentPool.ChildPoolSnapshotsAreNotReady.selector);
        _triggerDepositWithdrawProcess();
    }
}
