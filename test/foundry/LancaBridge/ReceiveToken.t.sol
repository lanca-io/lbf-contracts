// SPDX-License-Identifier: UNLICENSED
/* solhint-disable func-name-mixedcase */
pragma solidity 0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {IConceroRouter} from "@concero/v2-contracts/contracts/interfaces/IConceroRouter.sol";
import {MessageCodec} from "@concero/v2-contracts/contracts/common/libraries/MessageCodec.sol";

import {IBase} from "contracts/Base/interfaces/IBase.sol";
import {ILancaBridge} from "contracts/LancaBridge/interfaces/ILancaBridge.sol";
import {ICommonErrors} from "contracts/common/interfaces/ICommonErrors.sol";

import {LancaClientMock} from "../mocks/LancaClientMock.sol";
import {LancaBridgeBase} from "./LancaBridgeBase.sol";

contract ReceiveToken is LancaBridgeBase {
    using MessageCodec for IConceroRouter.MessageRequest;

    function setUp() public override {
        super.setUp();

        deal(address(usdc), address(parentPool), 1000e6);
        deal(address(usdc), address(childPool), 1000e6);
    }

    function test_ReceiveTokenToParentPool_Success() public {
        uint256 bridgeAmount = 100e6;
        address dstUser = makeAddr("dstUser");

        bytes memory message = abi.encode(
            IBase.ConceroMessageType.BRIDGE,
            abi.encode(user, dstUser, bridgeAmount, 0, 0, "")
        );

        uint256 parentPoolBalanceBefore = IERC20(usdc).balanceOf(address(parentPool));
        uint256 dstUserBalanceBefore = IERC20(usdc).balanceOf(dstUser);
        uint256 activeBalanceBefore = parentPool.getActiveBalance();
        IBase.LiqTokenDailyFlow memory flowBefore = IBase.LiqTokenDailyFlow({
            inflow: parentPool.getYesterdayFlow().inflow,
            outflow: parentPool.getYesterdayFlow().outflow
        });

        IConceroRouter.MessageRequest memory messageRequest = _buildMessageRequest(
            message,
            PARENT_POOL_CHAIN_SELECTOR,
            address(parentPool)
        );

        vm.expectEmit(false, true, true, true);
        emit ILancaBridge.BridgeDelivered(DEFAULT_MESSAGE_ID, bridgeAmount);

        vm.prank(conceroRouter);
        parentPool.conceroReceive(
            messageRequest.toMessageReceiptBytes(
                CHILD_POOL_CHAIN_SELECTOR,
                address(childPool),
                NONCE
            ),
            validationChecks,
            validatorLibs,
            relayerLib
        );

        uint256 parentPoolBalanceAfter = IERC20(usdc).balanceOf(address(parentPool));
        uint256 dstUserBalanceAfter = IERC20(usdc).balanceOf(dstUser);
        uint256 activeBalanceAfter = parentPool.getActiveBalance();

        assertEq(parentPoolBalanceAfter, parentPoolBalanceBefore - bridgeAmount);
        assertEq(dstUserBalanceAfter, dstUserBalanceBefore + bridgeAmount);
        assertEq(activeBalanceAfter, activeBalanceBefore - bridgeAmount);

        vm.warp(block.timestamp + 1 days);
        assertEq(parentPool.getYesterdayFlow().outflow, flowBefore.outflow + bridgeAmount);
    }

    function test_ReceiveTokenToChildPool_Success() public {
        uint256 bridgeAmount = 100e6;
        address dstUser = makeAddr("dstUser");

        bytes memory message = abi.encode(
            IBase.ConceroMessageType.BRIDGE,
            abi.encode(user, dstUser, bridgeAmount, 0, 0, "")
        );

        uint256 childPoolBalanceBefore = IERC20(usdc).balanceOf(address(childPool));
        uint256 dstUserBalanceBefore = IERC20(usdc).balanceOf(dstUser);
        uint256 activeBalanceBefore = childPool.getActiveBalance();
        IBase.LiqTokenDailyFlow memory flowBefore = IBase.LiqTokenDailyFlow({
            inflow: childPool.getYesterdayFlow().inflow,
            outflow: childPool.getYesterdayFlow().outflow
        });

        IConceroRouter.MessageRequest memory messageRequest = _buildMessageRequest(
            message,
            CHILD_POOL_CHAIN_SELECTOR,
            address(childPool)
        );

        vm.expectEmit(false, true, true, true);
        emit ILancaBridge.BridgeDelivered(DEFAULT_MESSAGE_ID, bridgeAmount);

        vm.prank(conceroRouter);
        childPool.conceroReceive(
            messageRequest.toMessageReceiptBytes(
                PARENT_POOL_CHAIN_SELECTOR,
                address(parentPool),
                NONCE
            ),
            validationChecks,
            validatorLibs,
            relayerLib
        );

        uint256 childPoolBalanceAfter = IERC20(usdc).balanceOf(address(childPool));
        uint256 dstUserBalanceAfter = IERC20(usdc).balanceOf(dstUser);
        uint256 activeBalanceAfter = childPool.getActiveBalance();

        assertEq(childPoolBalanceAfter, childPoolBalanceBefore - bridgeAmount);
        assertEq(dstUserBalanceAfter, dstUserBalanceBefore + bridgeAmount);
        assertEq(activeBalanceAfter, activeBalanceBefore - bridgeAmount);

        vm.warp(block.timestamp + 1 days);
        assertEq(childPool.getYesterdayFlow().outflow, flowBefore.outflow + bridgeAmount);
    }

    function test_handleConceroReceiveBridgeLiquidity_RevertsInvalidAmount() public {
        uint256 bridgeAmount = 2000e6;
        address dstUser = makeAddr("dstUser");

        bytes memory message = abi.encode(
            IBase.ConceroMessageType.BRIDGE,
            abi.encode(user, dstUser, bridgeAmount, 0, 0, "")
        );

        IConceroRouter.MessageRequest memory messageRequest = _buildMessageRequest(
            message,
            PARENT_POOL_CHAIN_SELECTOR,
            address(parentPool)
        );

        vm.expectRevert(ICommonErrors.InvalidAmount.selector);

        vm.prank(conceroRouter);
        parentPool.conceroReceive(
            messageRequest.toMessageReceiptBytes(
                CHILD_POOL_CHAIN_SELECTOR,
                address(childPool),
                NONCE
            ),
            validationChecks,
            validatorLibs,
            relayerLib
        );
    }

    function test_handleConceroReceiveBridgeLiquidity_ReorgScenario() public {
        uint256 originalAmount = 100e6;
        uint256 newAmount = 150e6;
        uint256 nonce = 123;
        address dstUser = makeAddr("dstUser");

        bytes memory firstMessage = abi.encode(
            IBase.ConceroMessageType.BRIDGE,
            abi.encode(user, dstUser, originalAmount, 0, nonce, "")
        );

        IConceroRouter.MessageRequest memory messageRequest = _buildMessageRequest(
            firstMessage,
            PARENT_POOL_CHAIN_SELECTOR,
            address(parentPool)
        );

        vm.prank(conceroRouter);
        parentPool.conceroReceive(
            messageRequest.toMessageReceiptBytes(
                CHILD_POOL_CHAIN_SELECTOR,
                address(childPool),
                NONCE
            ),
            validationChecks,
            validatorLibs,
            relayerLib
        );

        bytes memory reorgMessage = abi.encode(
            IBase.ConceroMessageType.BRIDGE,
            abi.encode(user, dstUser, newAmount, 0, nonce, "")
        );

        IConceroRouter.MessageRequest memory reorgMessageRequest = _buildMessageRequest(
            reorgMessage,
            PARENT_POOL_CHAIN_SELECTOR,
            address(parentPool)
        );

        vm.expectEmit(true, false, false, true);
        emit ILancaBridge.SrcBridgeReorged(CHILD_POOL_CHAIN_SELECTOR, originalAmount);

        vm.expectEmit(false, false, false, true);
        emit ILancaBridge.BridgeDelivered(DEFAULT_MESSAGE_ID, newAmount);

        vm.prank(conceroRouter);
        parentPool.conceroReceive(
            reorgMessageRequest.toMessageReceiptBytes(
                CHILD_POOL_CHAIN_SELECTOR,
                address(childPool),
                NONCE
            ),
            validationChecks,
            validatorLibs,
            relayerLib
        );
    }

    function test_handleConceroReceiveBridgeLiquidity_WithValidLancaClient() public {
        uint256 bridgeAmount = 100e6;
        uint256 dstGasLimit = 200_000;
        bytes memory dstCallData = abi.encode("test call data");

        LancaClientMock lancaClient = new LancaClientMock(address(parentPool));

        bytes memory message = abi.encode(
            IBase.ConceroMessageType.BRIDGE,
            abi.encode(user, address(lancaClient), bridgeAmount, dstGasLimit, 0, dstCallData)
        );

        uint256 parentPoolBalanceBefore = IERC20(usdc).balanceOf(address(parentPool));
        uint256 clientBalanceBefore = IERC20(usdc).balanceOf(address(lancaClient));

        vm.expectEmit(false, false, false, true);
        emit ILancaBridge.BridgeDelivered(DEFAULT_MESSAGE_ID, bridgeAmount);

        IConceroRouter.MessageRequest memory messageRequest = _buildMessageRequest(
            message,
            PARENT_POOL_CHAIN_SELECTOR,
            address(parentPool)
        );

        vm.prank(conceroRouter);
        parentPool.conceroReceive(
            messageRequest.toMessageReceiptBytes(
                CHILD_POOL_CHAIN_SELECTOR,
                address(childPool),
                NONCE
            ),
            validationChecks,
            validatorLibs,
            relayerLib
        );

        assertEq(
            IERC20(usdc).balanceOf(address(parentPool)),
            parentPoolBalanceBefore - bridgeAmount
        );
        assertEq(IERC20(usdc).balanceOf(address(lancaClient)), clientBalanceBefore + bridgeAmount);

        assertEq(lancaClient.getReceivedCallsCount(), 1);

        LancaClientMock.ReceivedCall memory call = lancaClient.getReceivedCall(0);
        assertEq(call.srcChainSelector, CHILD_POOL_CHAIN_SELECTOR);
        assertEq(call.sender, user);
        assertEq(call.amount, bridgeAmount);
        assertEq(call.data, dstCallData);
    }

    function test_handleConceroReceiveBridgeLiquidity_RevertsInvalidConceroMessage() public {
        uint256 bridgeAmount = 100e6;
        uint256 dstGasLimit = 50_000;
        bytes memory dstCallData = abi.encode("test call data");
        address invalidReceiver = makeAddr("invalidReceiver");

        bytes memory message = abi.encode(
            IBase.ConceroMessageType.BRIDGE,
            abi.encode(user, invalidReceiver, bridgeAmount, dstGasLimit, 0, dstCallData)
        );

        IConceroRouter.MessageRequest memory messageRequest = _buildMessageRequest(
            message,
            PARENT_POOL_CHAIN_SELECTOR,
            address(parentPool)
        );

        vm.expectRevert(ILancaBridge.InvalidConceroMessage.selector);

        vm.prank(conceroRouter);
        parentPool.conceroReceive(
            messageRequest.toMessageReceiptBytes(
                CHILD_POOL_CHAIN_SELECTOR,
                address(childPool),
                NONCE
            ),
            validationChecks,
            validatorLibs,
            relayerLib
        );
    }

    function test_handleConceroReceiveBridgeLiquidity_NoHookCall() public {
        uint256 bridgeAmount = 100e6;
        uint256 dstGasLimit = 0;
        bytes memory dstCallData = "";
        address dstUser = makeAddr("dstUser");

        bytes memory message = abi.encode(
            IBase.ConceroMessageType.BRIDGE,
            abi.encode(user, dstUser, bridgeAmount, dstGasLimit, 0, dstCallData)
        );

        uint256 parentPoolBalanceBefore = IERC20(usdc).balanceOf(address(parentPool));
        uint256 dstUserBalanceBefore = IERC20(usdc).balanceOf(dstUser);

        IConceroRouter.MessageRequest memory messageRequest = _buildMessageRequest(
            message,
            PARENT_POOL_CHAIN_SELECTOR,
            address(parentPool)
        );

        vm.expectEmit(false, false, false, true);
        emit ILancaBridge.BridgeDelivered(DEFAULT_MESSAGE_ID, bridgeAmount);

        vm.prank(conceroRouter);
        parentPool.conceroReceive(
            messageRequest.toMessageReceiptBytes(
                CHILD_POOL_CHAIN_SELECTOR,
                address(childPool),
                NONCE
            ),
            validationChecks,
            validatorLibs,
            relayerLib
        );

        assertEq(
            IERC20(usdc).balanceOf(address(parentPool)),
            parentPoolBalanceBefore - bridgeAmount
        );
        assertEq(IERC20(usdc).balanceOf(dstUser), dstUserBalanceBefore + bridgeAmount);
    }

    function test_handleConceroReceiveBridgeLiquidity_HookReverts() public {
        uint256 bridgeAmount = 100e6;
        uint256 dstGasLimit = 200_000;
        bytes memory dstCallData = abi.encode("test call data");
        string memory revertReason = "Test revert";

        LancaClientMock lancaClient = new LancaClientMock(address(parentPool));
        lancaClient.setShouldRevert(true, revertReason);

        uint256 parentPoolBalanceBefore = IERC20(usdc).balanceOf(address(parentPool));
        uint256 clientBalanceBefore = IERC20(usdc).balanceOf(address(lancaClient));

        bytes memory message = abi.encode(
            IBase.ConceroMessageType.BRIDGE,
            abi.encode(user, address(lancaClient), bridgeAmount, dstGasLimit, 0, dstCallData)
        );

        IConceroRouter.MessageRequest memory messageRequest = _buildMessageRequest(
            message,
            PARENT_POOL_CHAIN_SELECTOR,
            address(parentPool)
        );

        vm.expectRevert(abi.encode(revertReason));

        vm.prank(conceroRouter);
        parentPool.conceroReceive(
            messageRequest.toMessageReceiptBytes(
                CHILD_POOL_CHAIN_SELECTOR,
                address(childPool),
                NONCE
            ),
            validationChecks,
            validatorLibs,
            relayerLib
        );

        assertEq(IERC20(usdc).balanceOf(address(parentPool)), parentPoolBalanceBefore);
        assertEq(IERC20(usdc).balanceOf(address(lancaClient)), clientBalanceBefore);
    }
}
