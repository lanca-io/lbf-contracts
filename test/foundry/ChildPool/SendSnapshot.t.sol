// SPDX-License-Identifier: UNLICENSED
/* solhint-disable func-name-mixedcase */
pragma solidity 0.8.28;

import {ChildPool} from "contracts/ChildPool/ChildPool.sol";
import {IOUToken} from "contracts/Rebalancer/IOUToken.sol";
import {IParentPool} from "contracts/ParentPool/interfaces/IParentPool.sol";
import {IPoolBase} from "contracts/PoolBase/interfaces/IPoolBase.sol";
import {ChildPoolWrapper} from "contracts/test-helpers/ChildPoolWrapper.sol";

import {ChildPoolBase} from "./ChildPoolBase.sol";

contract SendSnapshot is ChildPoolBase {
    address public parentPool;

    function setUp() public override {
        super.setUp();

        parentPool = makeAddr("parentPool");

        vm.startPrank(deployer);
        childPool = new ChildPoolWrapper(
            conceroRouter,
            iouToken,
            address(usdc),
            6,
            CHILD_POOL_CHAIN_SELECTOR
        );

        childPool.setLancaKeeper(s_lancaKeeper);
        childPool.setDstPool(PARENT_POOL_CHAIN_SELECTOR, parentPool);
        vm.stopPrank();

        vm.deal(s_lancaKeeper, 1 ether);
    }

    function test_sendSnapshotToParentPool_Success() public {
        uint256 messageFee = childPool.getMessageFee(
            PARENT_POOL_CHAIN_SELECTOR,
            parentPool,
            GAS_LIMIT
        );

        // Allocate the balance
        deal(address(usdc), address(childPool), 1000e6);

        // Increase IOU totalSupply
        vm.startPrank(deployer);
        IOUToken(iouToken).grantRole(IOUToken(iouToken).MINTER_ROLE(), deployer);
        IOUToken(iouToken).mint(address(childPool), 100e6);
        vm.stopPrank();

        // Set daily flow
        uint256 inflow = 100e6;
        uint256 outflow = 200e6;

        ChildPoolWrapper(address(childPool)).setDailyFlow(inflow, outflow);

        // Set total IOU sent and received
        uint256 totalIouSent = 300e6;
        uint256 totalIouReceived = 400e6;

        ChildPoolWrapper(address(childPool)).setTotalIouSent(totalIouSent);
        ChildPoolWrapper(address(childPool)).setTotalIouReceived(totalIouReceived);

        // Create snapshot
        IParentPool.SnapshotSubmission memory snapshot = IParentPool.SnapshotSubmission({
            balance: childPool.getActiveBalance(),
            dailyFlow: childPool.getYesterdayFlow(),
            iouTotalSent: totalIouSent,
            iouTotalReceived: totalIouReceived,
            iouTotalSupply: IOUToken(iouToken).totalSupply(),
            timestamp: uint32(block.timestamp)
        });

        bytes32 messageId = keccak256(
            abi.encode(
                block.number,
                PARENT_POOL_CHAIN_SELECTOR,
                false,
                address(0),
                abi.encode(IPoolBase.ConceroMessageType.SEND_SNAPSHOT, abi.encode(snapshot))
            )
        );

        vm.expectEmit(true, true, true, true);
        emit ChildPool.SnapshotSent(messageId, PARENT_POOL_CHAIN_SELECTOR, snapshot);

        vm.prank(s_lancaKeeper);
        childPool.sendSnapshotToParentPool{value: messageFee}(PARENT_POOL_CHAIN_SELECTOR);
    }
}
