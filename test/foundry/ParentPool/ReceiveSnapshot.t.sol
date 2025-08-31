// SPDX-License-Identifier: UNLICENSED
/* solhint-disable func-name-mixedcase */
pragma solidity 0.8.28;

import {IBase} from "contracts/Base/interfaces/IBase.sol";
import {IParentPool} from "contracts/ParentPool/interfaces/IParentPool.sol";

import {ParentPoolBase} from "../ParentPool/ParentPoolBase.sol";

contract ReceiveSnapshot is ParentPoolBase {
    function setUp() public override {
        super.setUp();
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

        bytes32 messageId = keccak256(
            abi.encode(
                block.number,
                childPoolChainSelector_1,
                false,
                address(0),
                abi.encode(IBase.ConceroMessageType.SEND_SNAPSHOT, snapshot)
            )
        );

        vm.prank(conceroRouter);
        s_parentPool.conceroReceive(
            messageId,
            childPoolChainSelector_1,
            abi.encode(s_childPool_1),
            abi.encode(IBase.ConceroMessageType.SEND_SNAPSHOT, abi.encode(snapshot))
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
}
