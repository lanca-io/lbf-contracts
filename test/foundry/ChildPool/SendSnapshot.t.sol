// SPDX-License-Identifier: UNLICENSED
/* solhint-disable func-name-mixedcase */
pragma solidity 0.8.28;

import {ChildPool} from "contracts/ChildPool/ChildPool.sol";
import {IOUToken} from "contracts/Rebalancer/IOUToken.sol";
import {IParentPool} from "contracts/ParentPool/interfaces/IParentPool.sol";
import {IBase} from "contracts/Base/interfaces/IBase.sol";
import {ChildPoolWrapper} from "contracts/test-helpers/ChildPoolWrapper.sol";
import {ICommonErrors} from "contracts/common/interfaces/ICommonErrors.sol";
import {ChildPoolBase} from "./ChildPoolBase.sol";
import {BridgeCodec} from "contracts/common/libraries/BridgeCodec.sol";

contract SendSnapshot is ChildPoolBase {
    using BridgeCodec for address;

    address public parentPool;

    function setUp() public override {
        super.setUp();

        parentPool = makeAddr("parentPool");

        vm.startPrank(s_deployer);
        s_childPool = new ChildPoolWrapper(
            s_conceroRouter,
            address(s_iouToken),
            address(s_usdc),
            6,
            CHILD_POOL_CHAIN_SELECTOR,
            PARENT_POOL_CHAIN_SELECTOR
        );

        s_childPool.setLancaKeeper(s_lancaKeeper);
        s_childPool.setDstPool(PARENT_POOL_CHAIN_SELECTOR, parentPool.toBytes32());
        vm.stopPrank();

        vm.deal(s_lancaKeeper, 1 ether);
    }

    function test_sendSnapshotToParentPool_Success() public {
        uint256 messageFee = s_childPool.getBridgeIouNativeFee(PARENT_POOL_CHAIN_SELECTOR);

        // Allocate the balance
        deal(address(s_usdc), address(s_childPool), 1000e6);

        // Increase IOU totalSupply
        vm.startPrank(s_deployer);
        IOUToken(s_iouToken).grantRole(IOUToken(s_iouToken).MINTER_ROLE(), s_deployer);
        IOUToken(s_iouToken).mint(address(s_childPool), 100e6);
        vm.stopPrank();

        // Set daily flow
        uint256 inflow = 100e6;
        uint256 outflow = 200e6;

        ChildPoolWrapper(payable(s_childPool)).setDailyFlow(inflow, outflow);

        // Set total IOU sent and received
        uint256 totalIouSent = 300e6;
        uint256 totalIouReceived = 400e6;

        ChildPoolWrapper(payable(s_childPool)).setTotalIouSent(totalIouSent);
        ChildPoolWrapper(payable(s_childPool)).setTotalIouReceived(totalIouReceived);

        // Create snapshot
        IParentPool.ChildPoolSnapshot memory snapshot = IParentPool.ChildPoolSnapshot({
            balance: s_childPool.getActiveBalance(),
            dailyFlow: s_childPool.getYesterdayFlow(),
            iouTotalSent: totalIouSent,
            iouTotalReceived: totalIouReceived,
            iouTotalSupply: IOUToken(s_iouToken).totalSupply(),
            timestamp: uint32(block.timestamp),
            // todo: fill it
            totalLiqTokenReceived: 0,
            totalLiqTokenSent: 0
        });

        keccak256(
            abi.encode(
                block.number,
                PARENT_POOL_CHAIN_SELECTOR,
                false,
                address(0),
                abi.encode(IBase.ConceroMessageType.SEND_SNAPSHOT, abi.encode(snapshot))
            )
        );

        vm.prank(s_lancaKeeper);
        s_childPool.sendSnapshotToParentPool{value: messageFee}();
    }

    function test_sendSnapshotToParentPool_InvalidDstChainSelector() public {
        vm.startPrank(s_deployer);
        s_childPool = new ChildPoolWrapper(
            s_conceroRouter,
            address(s_iouToken),
            address(s_usdc),
            6,
            CHILD_POOL_CHAIN_SELECTOR,
            PARENT_POOL_CHAIN_SELECTOR
        );

        s_childPool.setLancaKeeper(s_lancaKeeper);
        vm.stopPrank();

        vm.prank(s_lancaKeeper);
        vm.expectRevert(
            abi.encodeWithSelector(
                ICommonErrors.InvalidDstChainSelector.selector,
                PARENT_POOL_CHAIN_SELECTOR
            )
        );
        s_childPool.sendSnapshotToParentPool{value: 0}();
    }

    function test_getSnapshotMessageFee() public view {
        uint256 messageFee = s_childPool.getSnapshotMessageFee();
        assertEq(messageFee, 0.0001 ether);
    }
}
