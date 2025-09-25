// SPDX-License-Identifier: UNLICENSED
/* solhint-disable func-name-mixedcase */
pragma solidity 0.8.28;

import {ICommonErrors} from "contracts/common/interfaces/ICommonErrors.sol";
import {IBase} from "contracts/Base/interfaces/IBase.sol";
import {ChildPoolWrapper} from "contracts/test-helpers/ChildPoolWrapper.sol";
import {ChildPoolBase} from "./ChildPoolBase.sol";

contract ChildPoolTest is ChildPoolBase {
    ChildPoolWrapper public childPoolWrapper;

    function setUp() public override {
        super.setUp();

        childPoolWrapper = new ChildPoolWrapper(
            conceroRouter,
            address(iouToken),
            address(usdc),
            6,
            CHILD_POOL_CHAIN_SELECTOR,
            PARENT_POOL_CHAIN_SELECTOR
        );

        vm.prank(deployer);
        childPoolWrapper.exposed_setDstPool(PARENT_POOL_CHAIN_SELECTOR, makeAddr("parentPool"));
    }

    /** -- Test Concero Receive Functions -- */

    function test_handleConceroReceiveUpdateTargetBalance() public {
        uint256 newTargetBalance = 500_000e6;

        bytes memory messagePayload = abi.encode(
            IBase.ConceroMessageType.UPDATE_TARGET_BALANCE,
            abi.encode(newTargetBalance)
        );

        vm.prank(conceroRouter);
        childPoolWrapper.conceroReceive(
            DEFAULT_MESSAGE_ID,
            PARENT_POOL_CHAIN_SELECTOR,
            abi.encode(makeAddr("parentPool")),
            messagePayload
        );

        assertEq(childPoolWrapper.getTargetBalance(), newTargetBalance);
    }

    function test_handleConceroReceiveSnapshot_RevertsFunctionNotImplemented() public {
        bytes memory snapshotData = abi.encode("");
        bytes memory messagePayload = abi.encode(
            IBase.ConceroMessageType.SEND_SNAPSHOT,
            snapshotData
        );

        vm.expectRevert(ICommonErrors.FunctionNotImplemented.selector);

        vm.prank(conceroRouter);
        childPoolWrapper.conceroReceive(
            DEFAULT_MESSAGE_ID,
            PARENT_POOL_CHAIN_SELECTOR,
            abi.encode(makeAddr("parentPool")),
            messagePayload
        );
    }

    function test_handleConceroReceiveUpdateTargetBalance_RevertsUnauthorizedSender() public {
        uint256 newTargetBalance = 500_000e6;
        address unauthorizedSender = makeAddr("unauthorizedSender");

        bytes memory messagePayload = abi.encode(
            IBase.ConceroMessageType.UPDATE_TARGET_BALANCE,
            abi.encode(newTargetBalance)
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                ICommonErrors.UnauthorizedSender.selector,
                unauthorizedSender,
                makeAddr("parentPool")
            )
        );

        vm.prank(conceroRouter);
        childPoolWrapper.conceroReceive(
            DEFAULT_MESSAGE_ID,
            PARENT_POOL_CHAIN_SELECTOR,
            abi.encode(unauthorizedSender),
            messagePayload
        );
    }
}
