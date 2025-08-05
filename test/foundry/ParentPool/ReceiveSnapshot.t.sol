// SPDX-License-Identifier: UNLICENSED
/* solhint-disable func-name-mixedcase */
pragma solidity 0.8.28;

import {IPoolBase} from "contracts/PoolBase/interfaces/IPoolBase.sol";
import {IParentPool} from "contracts/ParentPool/interfaces/IParentPool.sol";
import {ParentPoolWrapper} from "contracts/test-helpers/ParentPoolWrapper.sol";

import {ParentPoolBase} from "../ParentPool/ParentPoolBase.sol";

contract ReceiveSnapshot is ParentPoolBase {
    ParentPoolWrapper public parentPoolWrapper;

    function setUp() public override {
        super.setUp();

        vm.startPrank(deployer);
        parentPoolWrapper = new ParentPoolWrapper(
            address(usdc),
            6,
            address(lpToken),
            conceroRouter,
            PARENT_POOL_CHAIN_SELECTOR,
            address(iouToken)
        );

        parentPoolWrapper.setDstPool(childPoolChainSelector_1, s_childPool_1);
        vm.stopPrank();
    }

    function test_ReceiveSnapshot_Success() public {
        uint256 activeBalance = 100e6;
        uint256 inflow = 200e6;
        uint256 outflow = 300e6;
        uint256 iouTotalSent = 400e6;
        uint256 iouTotalReceived = 500e6;
        uint256 iouTotalSupply = 600e6;

        IPoolBase.LiqTokenDailyFlow memory dailyFlow = IPoolBase.LiqTokenDailyFlow({
            inflow: inflow,
            outflow: outflow
        });

        IParentPool.SnapshotSubmission memory snapshot = IParentPool.SnapshotSubmission({
            balance: activeBalance,
            dailyFlow: dailyFlow,
            iouTotalSent: iouTotalSent,
            iouTotalReceived: iouTotalReceived,
            iouTotalSupply: iouTotalSupply,
            timestamp: uint32(block.timestamp)
        });

        bytes32 messageId = keccak256(
            abi.encode(
                block.number,
                childPoolChainSelector_1,
                false,
                address(0),
                abi.encode(IPoolBase.ConceroMessageType.SEND_SNAPSHOT, snapshot)
            )
        );

        vm.expectEmit(true, true, true, true);
        emit IParentPool.SnapshotReceived(messageId, childPoolChainSelector_1, snapshot);

        vm.prank(conceroRouter);
        parentPoolWrapper.conceroReceive(
            messageId,
            childPoolChainSelector_1,
            abi.encode(s_childPool_1),
            abi.encode(IPoolBase.ConceroMessageType.SEND_SNAPSHOT, abi.encode(snapshot))
        );

        IParentPool.SnapshotSubmission memory receivedSnapshot = parentPoolWrapper
            .getChildPoolSubmission(childPoolChainSelector_1);

        assertEq(receivedSnapshot.balance, activeBalance);
        assertEq(receivedSnapshot.dailyFlow.inflow, inflow);
        assertEq(receivedSnapshot.dailyFlow.outflow, outflow);
        assertEq(receivedSnapshot.iouTotalSent, iouTotalSent);
        assertEq(receivedSnapshot.iouTotalReceived, iouTotalReceived);
        assertEq(receivedSnapshot.iouTotalSupply, iouTotalSupply);
        assertEq(receivedSnapshot.timestamp, uint32(block.timestamp));
    }
}
