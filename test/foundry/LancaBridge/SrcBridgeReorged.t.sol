//// SPDX-License-Identifier: UNLICENSED
///* solhint-disable func-name-mixedcase */
//pragma solidity 0.8.28;
//
//import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
//
//import {ILancaBridge} from "contracts/LancaBridge/interfaces/ILancaBridge.sol";
//import {IBase} from "contracts/Base/interfaces/IBase.sol";
//import {LancaBridgeBase} from "./LancaBridgeBase.sol";
//import {Vm} from "forge-std/src/Vm.sol";
//
//
//contract SrcBridgeReorgedTest is LancaBridgeBase {
//    uint256 constant BRIDGE_AMOUNT = 100e6;
//    uint256 constant DIFFERENT_BRIDGE_AMOUNT = 150e6;
//    uint24 constant SOURCE_CHAIN = 12345;
//    uint256 constant NONCE = 42;
//
//    function setUp() public override {
//        super.setUp();
//
//        // Ensure pools have enough liquidity
//        deal(address(usdc), address(parentPool), 1000e6);
//        deal(address(usdc), address(childPool), 1000e6);
//    }
//
//    function test_SrcBridgeReorged_NotEmittedOnFirstReceive() public {
//        address tokenReceiver = makeAddr("tokenReceiver");
//
//        bytes memory message = abi.encode(
//            IBase.ConceroMessageType.BRIDGE,
//            abi.encode(usdc, user, tokenReceiver, BRIDGE_AMOUNT, 0, NONCE, "")
//        );
//
//        // First receive - should NOT emit SrcBridgeReorged
//        vm.expectEmit(true, true, true, true);
//        emit ILancaBridge.BridgeDelivered(
//            DEFAULT_MESSAGE_ID,
//            SOURCE_CHAIN,
//            address(usdc),
//            user,
//            tokenReceiver,
//            BRIDGE_AMOUNT
//        );
//
//        // Should not emit SrcBridgeReorged
//        vm.recordLogs();
//
//        vm.prank(conceroRouter);
//        childPool.conceroReceive(
//            DEFAULT_MESSAGE_ID,
//            SOURCE_CHAIN,
//            abi.encode(address(parentPool)),
//            message
//        );
//
//        Vm.Log[] memory entries = vm.getRecordedLogs();
//
//        // Verify no SrcBridgeReorged event was emitted
//        for (uint256 i = 0; i < entries.length; i++) {
//            assertNotEq(
//                entries[i].topics[0],
//                keccak256("SrcBridgeReorged(uint256,uint256,uint24)")
//            );
//        }
//    }
//
//    function test_SrcBridgeReorged_EmittedOnReorg() public {
//        address tokenReceiver = makeAddr("tokenReceiver");
//
//        // First message - initial bridge
//        bytes memory firstMessage = abi.encode(
//            IBase.ConceroMessageType.BRIDGE,
//            abi.encode(usdc, user, tokenReceiver, BRIDGE_AMOUNT, 0, NONCE, "")
//        );
//
//        // First receive
//        vm.prank(conceroRouter);
//        childPool.conceroReceive(
//            DEFAULT_MESSAGE_ID,
//            SOURCE_CHAIN,
//            abi.encode(address(parentPool)),
//            firstMessage
//        );
//
//        // Second message - reorg with different amount
//        bytes memory secondMessage = abi.encode(
//            IBase.ConceroMessageType.BRIDGE,
//            abi.encode(usdc, user, tokenReceiver, DIFFERENT_BRIDGE_AMOUNT, 0, NONCE, "")
//        );
//
//        bytes32 secondMessageId = keccak256("second_message");
//
//        // Expect SrcBridgeReorged event to be emitted
//        vm.expectEmit(true, true, true, true);
//        emit ILancaBridge.SrcBridgeReorged(
//            BRIDGE_AMOUNT, // oldAmount
//            DIFFERENT_BRIDGE_AMOUNT, // newAmount
//            SOURCE_CHAIN
//        );
//
//        // Also expect BridgeDelivered
//        vm.expectEmit(true, true, true, true);
//        emit ILancaBridge.BridgeDelivered(
//            secondMessageId,
//            SOURCE_CHAIN,
//            address(usdc),
//            user,
//            tokenReceiver,
//            DIFFERENT_BRIDGE_AMOUNT
//        );
//
//        vm.prank(conceroRouter);
//        childPool.conceroReceive(
//            secondMessageId,
//            SOURCE_CHAIN,
//            abi.encode(address(parentPool)),
//            secondMessage
//        );
//    }
//
//    function test_SrcBridgeReorged_EmittedOnReorgWithParentPool() public {
//        address tokenReceiver = makeAddr("tokenReceiver");
//
//        // First message - initial bridge
//        bytes memory firstMessage = abi.encode(
//            IBase.ConceroMessageType.BRIDGE,
//            abi.encode(usdc, user, tokenReceiver, BRIDGE_AMOUNT, 0, NONCE, "")
//        );
//
//        // First receive
//        vm.prank(conceroRouter);
//        parentPool.conceroReceive(
//            DEFAULT_MESSAGE_ID,
//            SOURCE_CHAIN,
//            abi.encode(address(childPool)),
//            firstMessage
//        );
//
//        // Second message - reorg with different amount
//        bytes memory secondMessage = abi.encode(
//            IBase.ConceroMessageType.BRIDGE,
//            abi.encode(usdc, user, tokenReceiver, DIFFERENT_BRIDGE_AMOUNT, 0, NONCE, "")
//        );
//
//        bytes32 secondMessageId = keccak256("second_message");
//
//        // Expect SrcBridgeReorged event to be emitted
//        vm.expectEmit(true, true, true, true);
//        emit ILancaBridge.SrcBridgeReorged(
//            BRIDGE_AMOUNT, // oldAmount
//            DIFFERENT_BRIDGE_AMOUNT, // newAmount
//            SOURCE_CHAIN
//        );
//
//        vm.prank(conceroRouter);
//        parentPool.conceroReceive(
//            secondMessageId,
//            SOURCE_CHAIN,
//            abi.encode(address(childPool)),
//            secondMessage
//        );
//    }
//
//    function test_SrcBridgeReorged_CorrectTotalReceivedCalculation() public {
//        address tokenReceiver = makeAddr("tokenReceiver");
//
//        uint256 totalReceivedBefore = childPool.getTotalReceived();
//
//        // First message - initial bridge
//        bytes memory firstMessage = abi.encode(
//            IBase.ConceroMessageType.BRIDGE,
//            abi.encode(usdc, user, tokenReceiver, BRIDGE_AMOUNT, 0, NONCE, "")
//        );
//
//        vm.prank(conceroRouter);
//        childPool.conceroReceive(
//            DEFAULT_MESSAGE_ID,
//            SOURCE_CHAIN,
//            abi.encode(address(parentPool)),
//            firstMessage
//        );
//
//        uint256 totalReceivedAfterFirst = childPool.getTotalReceived();
//        assertEq(totalReceivedAfterFirst, totalReceivedBefore + BRIDGE_AMOUNT);
//
//        // Second message - reorg with different amount
//        bytes memory secondMessage = abi.encode(
//            IBase.ConceroMessageType.BRIDGE,
//            abi.encode(usdc, user, tokenReceiver, DIFFERENT_BRIDGE_AMOUNT, 0, NONCE, "")
//        );
//
//        vm.prank(conceroRouter);
//        childPool.conceroReceive(
//            keccak256("second_message"),
//            SOURCE_CHAIN,
//            abi.encode(address(parentPool)),
//            secondMessage
//        );
//
//        uint256 totalReceivedAfterSecond = childPool.getTotalReceived();
//        assertEq(totalReceivedAfterSecond, totalReceivedBefore + DIFFERENT_BRIDGE_AMOUNT);
//    }
//
//    function test_SrcBridgeReorged_NoEventWhenSameAmount() public {
//        address tokenReceiver = makeAddr("tokenReceiver");
//
//        // First message - initial bridge
//        bytes memory firstMessage = abi.encode(
//            IBase.ConceroMessageType.BRIDGE,
//            abi.encode(usdc, user, tokenReceiver, BRIDGE_AMOUNT, 0, NONCE, "")
//        );
//
//        vm.prank(conceroRouter);
//        childPool.conceroReceive(
//            DEFAULT_MESSAGE_ID,
//            SOURCE_CHAIN,
//            abi.encode(address(parentPool)),
//            firstMessage
//        );
//
//        // Second message - same amount and nonce (no actual reorg)
//        bytes memory secondMessage = abi.encode(
//            IBase.ConceroMessageType.BRIDGE,
//            abi.encode(usdc, user, tokenReceiver, BRIDGE_AMOUNT, 0, NONCE, "")
//        );
//
//        vm.recordLogs();
//
//        vm.prank(conceroRouter);
//        childPool.conceroReceive(
//            keccak256("second_message"),
//            SOURCE_CHAIN,
//            abi.encode(address(parentPool)),
//            secondMessage
//        );
//
//        Vm.Log[] memory entries = vm.getRecordedLogs();
//
//        // Verify no SrcBridgeReorged event was emitted
//        for (uint256 i = 0; i < entries.length; i++) {
//            assertNotEq(
//                entries[i].topics[0],
//                keccak256("SrcBridgeReorged(uint256,uint256,uint24)")
//            );
//        }
//    }
//}
