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
import {BridgeCodec} from "contracts/common/libraries/BridgeCodec.sol";

contract ReceiveToken is LancaBridgeBase {
    using MessageCodec for IConceroRouter.MessageRequest;

    function setUp() public override {
        super.setUp();

        deal(address(s_usdc), address(s_parentPool), 1000e6);
        deal(address(s_usdc), address(s_childPool), 1000e6);
    }

    function test_ReceiveTokenToParentPool_gas() public {
        vm.pauseGasMetering();

        uint256 bridgeAmount = 100e6;
        address dstUser = makeAddr("dstUser");

        IConceroRouter.MessageRequest memory messageRequest = _buildMessageRequest(
            BridgeCodec.encodeBridgeData(
                s_user,
                bridgeAmount,
                USDC_TOKEN_DECIMALS,
                MessageCodec.encodeEvmDstChainData(dstUser, 0),
                ""
            ),
            PARENT_POOL_CHAIN_SELECTOR,
            address(s_parentPool)
        );

        vm.prank(s_conceroRouter);
        vm.resumeGasMetering();
        s_parentPool.conceroReceive(
            messageRequest.toMessageReceiptBytes(
                CHILD_POOL_CHAIN_SELECTOR,
                address(s_childPool),
                NONCE
            ),
            s_validationChecks,
            s_validatorLibs,
            s_relayerLib
        );
    }

    function test_ReceiveTokenToChildPool_gas() public {
        vm.pauseGasMetering();

        uint256 bridgeAmount = 100e6;
        address dstUser = makeAddr("dstUser");

        IConceroRouter.MessageRequest memory messageRequest = _buildMessageRequest(
            BridgeCodec.encodeBridgeData(
                s_user,
                bridgeAmount,
                USDC_TOKEN_DECIMALS,
                MessageCodec.encodeEvmDstChainData(dstUser, 0),
                ""
            ),
            CHILD_POOL_CHAIN_SELECTOR,
            address(s_childPool)
        );

        vm.prank(s_conceroRouter);
        vm.resumeGasMetering();
        s_childPool.conceroReceive(
            messageRequest.toMessageReceiptBytes(
                PARENT_POOL_CHAIN_SELECTOR,
                address(s_parentPool),
                NONCE
            ),
            s_validationChecks,
            s_validatorLibs,
            s_relayerLib
        );
    }

    function test_ReceiveTokenToParentPool_Success() public {
        uint256 bridgeAmount = 100e6;
        address dstUser = makeAddr("dstUser");

        uint256 parentPoolBalanceBefore = IERC20(s_usdc).balanceOf(address(s_parentPool));
        uint256 dstUserBalanceBefore = IERC20(s_usdc).balanceOf(dstUser);
        uint256 activeBalanceBefore = s_parentPool.getActiveBalance();
        IBase.LiqTokenDailyFlow memory flowBefore = IBase.LiqTokenDailyFlow({
            inflow: s_parentPool.getYesterdayFlow().inflow,
            outflow: s_parentPool.getYesterdayFlow().outflow
        });

        IConceroRouter.MessageRequest memory messageRequest = _buildMessageRequest(
            BridgeCodec.encodeBridgeData(
                s_user,
                bridgeAmount,
                USDC_TOKEN_DECIMALS,
                MessageCodec.encodeEvmDstChainData(dstUser, 0),
                ""
            ),
            PARENT_POOL_CHAIN_SELECTOR,
            address(s_parentPool)
        );

        vm.expectEmit(false, true, true, true);
        emit ILancaBridge.BridgeDelivered(DEFAULT_MESSAGE_ID, bridgeAmount);

        vm.prank(s_conceroRouter);
        s_parentPool.conceroReceive(
            messageRequest.toMessageReceiptBytes(
                CHILD_POOL_CHAIN_SELECTOR,
                address(s_childPool),
                NONCE
            ),
            s_validationChecks,
            s_validatorLibs,
            s_relayerLib
        );

        uint256 parentPoolBalanceAfter = IERC20(s_usdc).balanceOf(address(s_parentPool));
        uint256 dstUserBalanceAfter = IERC20(s_usdc).balanceOf(dstUser);
        uint256 activeBalanceAfter = s_parentPool.getActiveBalance();

        assertEq(parentPoolBalanceAfter, parentPoolBalanceBefore - bridgeAmount);
        assertEq(dstUserBalanceAfter, dstUserBalanceBefore + bridgeAmount);
        assertEq(activeBalanceAfter, activeBalanceBefore - bridgeAmount);

        vm.warp(block.timestamp + 1 days);
        assertEq(s_parentPool.getYesterdayFlow().outflow, flowBefore.outflow + bridgeAmount);
    }

    function test_ReceiveTokenToChildPool_Success() public {
        uint256 bridgeAmount = 100e6;
        address dstUser = makeAddr("dstUser");

        uint256 childPoolBalanceBefore = IERC20(s_usdc).balanceOf(address(s_childPool));
        uint256 dstUserBalanceBefore = IERC20(s_usdc).balanceOf(dstUser);
        uint256 activeBalanceBefore = s_childPool.getActiveBalance();
        IBase.LiqTokenDailyFlow memory flowBefore = IBase.LiqTokenDailyFlow({
            inflow: s_childPool.getYesterdayFlow().inflow,
            outflow: s_childPool.getYesterdayFlow().outflow
        });

        IConceroRouter.MessageRequest memory messageRequest = _buildMessageRequest(
            BridgeCodec.encodeBridgeData(
                s_user,
                bridgeAmount,
                USDC_TOKEN_DECIMALS,
                MessageCodec.encodeEvmDstChainData(dstUser, 0),
                ""
            ),
            CHILD_POOL_CHAIN_SELECTOR,
            address(s_childPool)
        );

        vm.expectEmit(false, true, true, true);
        emit ILancaBridge.BridgeDelivered(DEFAULT_MESSAGE_ID, bridgeAmount);

        vm.prank(s_conceroRouter);
        s_childPool.conceroReceive(
            messageRequest.toMessageReceiptBytes(
                PARENT_POOL_CHAIN_SELECTOR,
                address(s_parentPool),
                NONCE
            ),
            s_validationChecks,
            s_validatorLibs,
            s_relayerLib
        );

        uint256 childPoolBalanceAfter = IERC20(s_usdc).balanceOf(address(s_childPool));
        uint256 dstUserBalanceAfter = IERC20(s_usdc).balanceOf(dstUser);
        uint256 activeBalanceAfter = s_childPool.getActiveBalance();

        assertEq(childPoolBalanceAfter, childPoolBalanceBefore - bridgeAmount);
        assertEq(dstUserBalanceAfter, dstUserBalanceBefore + bridgeAmount);
        assertEq(activeBalanceAfter, activeBalanceBefore - bridgeAmount);

        vm.warp(block.timestamp + 1 days);
        assertEq(s_childPool.getYesterdayFlow().outflow, flowBefore.outflow + bridgeAmount);
    }

    function test_handleConceroReceiveBridgeLiquidity_RevertsInvalidAmount() public {
        uint256 bridgeAmount = 2000e6;
        address dstUser = makeAddr("dstUser");

        IConceroRouter.MessageRequest memory messageRequest = _buildMessageRequest(
            BridgeCodec.encodeBridgeData(
                s_user,
                bridgeAmount,
                USDC_TOKEN_DECIMALS,
                MessageCodec.encodeEvmDstChainData(dstUser, 0),
                ""
            ),
            PARENT_POOL_CHAIN_SELECTOR,
            address(s_parentPool)
        );

        vm.expectRevert(ICommonErrors.InvalidAmount.selector);

        vm.prank(s_conceroRouter);
        s_parentPool.conceroReceive(
            messageRequest.toMessageReceiptBytes(
                CHILD_POOL_CHAIN_SELECTOR,
                address(s_childPool),
                NONCE
            ),
            s_validationChecks,
            s_validatorLibs,
            s_relayerLib
        );
    }

    function test_handleConceroReceiveBridgeLiquidity_ReorgScenario() public {
        uint256 originalAmount = 100e6;
        uint256 newAmount = 150e6;
        uint256 nonce = 123;
        address dstUser = makeAddr("dstUser");

        bytes memory firstMessage = BridgeCodec.encodeBridgeData(
            s_user,
            originalAmount,
            USDC_TOKEN_DECIMALS,
            MessageCodec.encodeEvmDstChainData(dstUser, 0),
            ""
        );

        IConceroRouter.MessageRequest memory messageRequest = _buildMessageRequest(
            firstMessage,
            PARENT_POOL_CHAIN_SELECTOR,
            address(s_parentPool)
        );

        vm.prank(s_conceroRouter);
        s_parentPool.conceroReceive(
            messageRequest.toMessageReceiptBytes(
                CHILD_POOL_CHAIN_SELECTOR,
                address(s_childPool),
                NONCE
            ),
            s_validationChecks,
            s_validatorLibs,
            s_relayerLib
        );

        bytes memory reorgMessage = BridgeCodec.encodeBridgeData(
            s_user,
            newAmount,
            USDC_TOKEN_DECIMALS,
            MessageCodec.encodeEvmDstChainData(dstUser, 0),
            ""
        );

        IConceroRouter.MessageRequest memory reorgMessageRequest = _buildMessageRequest(
            reorgMessage,
            PARENT_POOL_CHAIN_SELECTOR,
            address(s_parentPool)
        );

        vm.expectEmit(true, false, false, true);
        emit ILancaBridge.SrcBridgeReorged(CHILD_POOL_CHAIN_SELECTOR, originalAmount);

        vm.expectEmit(false, false, false, true);
        emit ILancaBridge.BridgeDelivered(DEFAULT_MESSAGE_ID, newAmount);

        vm.prank(s_conceroRouter);
        s_parentPool.conceroReceive(
            reorgMessageRequest.toMessageReceiptBytes(
                CHILD_POOL_CHAIN_SELECTOR,
                address(s_childPool),
                NONCE
            ),
            s_validationChecks,
            s_validatorLibs,
            s_relayerLib
        );
    }

    function test_handleConceroReceiveBridgeLiquidity_WithValidLancaClient() public {
        uint256 bridgeAmount = 100e6;
        uint32 dstGasLimit = 200_000;
        bytes memory dstCallData = abi.encode("test call data");

        LancaClientMock lancaClient = new LancaClientMock(address(s_parentPool));

        uint256 parentPoolBalanceBefore = IERC20(s_usdc).balanceOf(address(s_parentPool));
        uint256 clientBalanceBefore = IERC20(s_usdc).balanceOf(address(lancaClient));

        vm.expectEmit(false, false, false, true);
        emit ILancaBridge.BridgeDelivered(DEFAULT_MESSAGE_ID, bridgeAmount);

        IConceroRouter.MessageRequest memory messageRequest = _buildMessageRequest(
            BridgeCodec.encodeBridgeData(
                s_user,
                bridgeAmount,
                USDC_TOKEN_DECIMALS,
                MessageCodec.encodeEvmDstChainData(address(lancaClient), dstGasLimit),
                dstCallData
            ),
            PARENT_POOL_CHAIN_SELECTOR,
            address(s_parentPool)
        );

        vm.prank(s_conceroRouter);
        s_parentPool.conceroReceive(
            messageRequest.toMessageReceiptBytes(
                CHILD_POOL_CHAIN_SELECTOR,
                address(s_childPool),
                NONCE
            ),
            s_validationChecks,
            s_validatorLibs,
            s_relayerLib
        );

        assertEq(
            IERC20(s_usdc).balanceOf(address(s_parentPool)),
            parentPoolBalanceBefore - bridgeAmount
        );
        assertEq(
            IERC20(s_usdc).balanceOf(address(lancaClient)),
            clientBalanceBefore + bridgeAmount
        );

        assertEq(lancaClient.getReceivedCallsCount(), 1);

        LancaClientMock.ReceivedCall memory call = lancaClient.getReceivedCall(0);
        assertEq(call.srcChainSelector, CHILD_POOL_CHAIN_SELECTOR);
        assertEq(call.sender, s_user);
        assertEq(call.amount, bridgeAmount);
        assertEq(call.data, dstCallData);
    }

    function test_handleConceroReceiveBridgeLiquidity_RevertsInvalidConceroMessage() public {
        uint256 bridgeAmount = 100e6;
        uint32 dstGasLimit = 50_000;
        bytes memory dstCallData = abi.encode("test call data");
        address invalidReceiver = makeAddr("invalidReceiver");

        IConceroRouter.MessageRequest memory messageRequest = _buildMessageRequest(
            BridgeCodec.encodeBridgeData(
                s_user,
                bridgeAmount,
                USDC_TOKEN_DECIMALS,
                MessageCodec.encodeEvmDstChainData(invalidReceiver, dstGasLimit),
                dstCallData
            ),
            PARENT_POOL_CHAIN_SELECTOR,
            address(s_parentPool)
        );

        vm.expectRevert(ILancaBridge.InvalidConceroMessage.selector);

        vm.prank(s_conceroRouter);
        s_parentPool.conceroReceive(
            messageRequest.toMessageReceiptBytes(
                CHILD_POOL_CHAIN_SELECTOR,
                address(s_childPool),
                NONCE
            ),
            s_validationChecks,
            s_validatorLibs,
            s_relayerLib
        );
    }

    function test_handleConceroReceiveBridgeLiquidity_NoHookCall() public {
        uint256 bridgeAmount = 100e6;
        uint32 dstGasLimit = 0;
        bytes memory dstCallData = "";
        address dstUser = makeAddr("dstUser");

        uint256 parentPoolBalanceBefore = IERC20(s_usdc).balanceOf(address(s_parentPool));
        uint256 dstUserBalanceBefore = IERC20(s_usdc).balanceOf(dstUser);

        IConceroRouter.MessageRequest memory messageRequest = _buildMessageRequest(
            BridgeCodec.encodeBridgeData(
                s_user,
                bridgeAmount,
                USDC_TOKEN_DECIMALS,
                MessageCodec.encodeEvmDstChainData(dstUser, dstGasLimit),
                dstCallData
            ),
            PARENT_POOL_CHAIN_SELECTOR,
            address(s_parentPool)
        );

        vm.expectEmit(false, false, false, true);
        emit ILancaBridge.BridgeDelivered(DEFAULT_MESSAGE_ID, bridgeAmount);

        vm.prank(s_conceroRouter);
        s_parentPool.conceroReceive(
            messageRequest.toMessageReceiptBytes(
                CHILD_POOL_CHAIN_SELECTOR,
                address(s_childPool),
                NONCE
            ),
            s_validationChecks,
            s_validatorLibs,
            s_relayerLib
        );

        assertEq(
            IERC20(s_usdc).balanceOf(address(s_parentPool)),
            parentPoolBalanceBefore - bridgeAmount
        );
        assertEq(IERC20(s_usdc).balanceOf(dstUser), dstUserBalanceBefore + bridgeAmount);
    }

    function test_handleConceroReceiveBridgeLiquidity_HookReverts() public {
        uint256 bridgeAmount = 100e6;
        uint32 dstGasLimit = 200_000;
        bytes memory dstCallData = abi.encode("test call data");
        string memory revertReason = "Test revert";

        LancaClientMock lancaClient = new LancaClientMock(address(s_parentPool));
        lancaClient.setShouldRevert(true, revertReason);

        uint256 parentPoolBalanceBefore = IERC20(s_usdc).balanceOf(address(s_parentPool));
        uint256 clientBalanceBefore = IERC20(s_usdc).balanceOf(address(lancaClient));

        IConceroRouter.MessageRequest memory messageRequest = _buildMessageRequest(
            BridgeCodec.encodeBridgeData(
                s_user,
                bridgeAmount,
                USDC_TOKEN_DECIMALS,
                MessageCodec.encodeEvmDstChainData(address(lancaClient), dstGasLimit),
                dstCallData
            ),
            PARENT_POOL_CHAIN_SELECTOR,
            address(s_parentPool)
        );

        vm.expectRevert(abi.encode(revertReason));

        vm.prank(s_conceroRouter);
        s_parentPool.conceroReceive(
            messageRequest.toMessageReceiptBytes(
                CHILD_POOL_CHAIN_SELECTOR,
                address(s_childPool),
                NONCE
            ),
            s_validationChecks,
            s_validatorLibs,
            s_relayerLib
        );

        assertEq(IERC20(s_usdc).balanceOf(address(s_parentPool)), parentPoolBalanceBefore);
        assertEq(IERC20(s_usdc).balanceOf(address(lancaClient)), clientBalanceBefore);
    }
}
