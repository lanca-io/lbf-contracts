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
import {Decimals} from "contracts/common/libraries/Decimals.sol";

import {MockERC20} from "../mocks/MockERC20.sol";

import {console} from "forge-std/src/console.sol";

contract ReceiveToken is LancaBridgeBase {
    using MessageCodec for IConceroRouter.MessageRequest;
    using Decimals for uint256;

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
            BridgeCodec.encodeBridgeData(s_user, dstUser, bridgeAmount, USDC_TOKEN_DECIMALS, ""),
            PARENT_POOL_CHAIN_SELECTOR,
            address(s_parentPool)
        );

        vm.prank(s_conceroRouter);
        vm.resumeGasMetering();
        s_parentPool.conceroReceive(
            messageRequest.toMessageReceiptBytes(
                CHILD_POOL_CHAIN_SELECTOR,
                address(s_childPool),
                NONCE,
                s_internalValidatorConfigs
            ),
            s_validationChecks,
            s_validatorLibs,
            s_relayerLib
        );
    }

    function test_ReceiveTokenToChildPool_gas() public {
        vm.pauseGasMetering();

        uint256 bridgeAmount = 100 * STD_TOKEN_DECIMALS_SCALE;
        address dstUser = makeAddr("dstUser");

        IConceroRouter.MessageRequest memory messageRequest = _buildMessageRequest(
            BridgeCodec.encodeBridgeData(s_user, dstUser, bridgeAmount, STD_TOKEN_DECIMALS, ""),
            CHILD_POOL_CHAIN_SELECTOR,
            address(s_childPool)
        );

        vm.prank(s_conceroRouter);
        vm.resumeGasMetering();
        s_childPool.conceroReceive(
            messageRequest.toMessageReceiptBytes(
                PARENT_POOL_CHAIN_SELECTOR,
                address(s_parentPool),
                NONCE,
                s_internalValidatorConfigs
            ),
            s_validationChecks,
            s_validatorLibs,
            s_relayerLib
        );
    }

    function testFuzz_ReceiveTokenToParentPool_Success(uint64 bridgeAmount) public {
        deal(address(s_usdc), address(s_parentPool), bridgeAmount);
        address dstUser = makeAddr("dstUser");

        uint256 parentPoolBalanceBefore = IERC20(s_usdc).balanceOf(address(s_parentPool));
        uint256 dstUserBalanceBefore = IERC20(s_usdc).balanceOf(dstUser);
        uint256 activeBalanceBefore = s_parentPool.getActiveBalance();
        IBase.LiqTokenDailyFlow memory flowBefore = IBase.LiqTokenDailyFlow({
            inflow: s_parentPool.getYesterdayFlow().inflow,
            outflow: s_parentPool.getYesterdayFlow().outflow
        });

        IConceroRouter.MessageRequest memory messageRequest = _buildMessageRequest(
            BridgeCodec.encodeBridgeData(s_user, dstUser, bridgeAmount, STD_TOKEN_DECIMALS, ""),
            PARENT_POOL_CHAIN_SELECTOR,
            address(s_parentPool)
        );

        uint256 bridgeAmountInUsdcTokenDecimals = uint256(bridgeAmount).toDecimals(
            STD_TOKEN_DECIMALS,
            USDC_TOKEN_DECIMALS
        );

        vm.expectEmit(false, true, true, true);
        emit ILancaBridge.BridgeDelivered(DEFAULT_MESSAGE_ID, bridgeAmountInUsdcTokenDecimals);

        vm.prank(s_conceroRouter);
        s_parentPool.conceroReceive(
            messageRequest.toMessageReceiptBytes(
                CHILD_POOL_CHAIN_SELECTOR,
                address(s_childPool),
                NONCE,
                s_internalValidatorConfigs
            ),
            s_validationChecks,
            s_validatorLibs,
            s_relayerLib
        );

        uint256 parentPoolBalanceAfter = IERC20(s_usdc).balanceOf(address(s_parentPool));
        uint256 dstUserBalanceAfter = IERC20(s_usdc).balanceOf(dstUser);
        uint256 activeBalanceAfter = s_parentPool.getActiveBalance();

        assertEq(parentPoolBalanceAfter, parentPoolBalanceBefore - bridgeAmountInUsdcTokenDecimals);
        assertEq(dstUserBalanceAfter, dstUserBalanceBefore + bridgeAmountInUsdcTokenDecimals);
        assertEq(activeBalanceAfter, activeBalanceBefore - bridgeAmountInUsdcTokenDecimals);

        vm.warp(block.timestamp + 1 days);
        assertEq(
            s_parentPool.getYesterdayFlow().outflow,
            flowBefore.outflow + bridgeAmountInUsdcTokenDecimals
        );
    }

    function testFuzz_ReceiveTokenToChildPool_Success(uint64 bridgeAmountInStdDecimals) public {
        uint256 amountInUsdcDecimals = uint256(bridgeAmountInStdDecimals).toDecimals(
            STD_TOKEN_DECIMALS,
            USDC_TOKEN_DECIMALS
        );
        vm.assume(amountInUsdcDecimals > 0);

        address dstUser = makeAddr("dstUser");

        uint256 truncatedBridgeAmount = amountInUsdcDecimals.toDecimals(
            USDC_TOKEN_DECIMALS,
            STD_TOKEN_DECIMALS
        );

        uint256 childPoolBalanceBefore = s_18DecUsdc.balanceOf(address(s_childPool));
        uint256 dstUserBalanceBefore = s_18DecUsdc.balanceOf(dstUser);
        uint256 activeBalanceBefore = s_childPool.getActiveBalance();
        IBase.LiqTokenDailyFlow memory flowBefore = IBase.LiqTokenDailyFlow({
            inflow: s_childPool.getYesterdayFlow().inflow,
            outflow: s_childPool.getYesterdayFlow().outflow
        });

        IConceroRouter.MessageRequest memory messageRequest = _buildMessageRequest(
            BridgeCodec.encodeBridgeData(
                s_user,
                dstUser,
                amountInUsdcDecimals,
                USDC_TOKEN_DECIMALS,
                ""
            ),
            CHILD_POOL_CHAIN_SELECTOR,
            address(s_childPool)
        );

        vm.expectEmit(false, true, true, true);
        emit ILancaBridge.BridgeDelivered(DEFAULT_MESSAGE_ID, truncatedBridgeAmount);

        vm.prank(s_conceroRouter);
        s_childPool.conceroReceive(
            messageRequest.toMessageReceiptBytes(
                PARENT_POOL_CHAIN_SELECTOR,
                address(s_parentPool),
                NONCE,
                s_internalValidatorConfigs
            ),
            s_validationChecks,
            s_validatorLibs,
            s_relayerLib
        );

        uint256 childPoolBalanceAfter = s_18DecUsdc.balanceOf(address(s_childPool));
        uint256 dstUserBalanceAfter = s_18DecUsdc.balanceOf(dstUser);
        uint256 activeBalanceAfter = s_childPool.getActiveBalance();

        assertEq(childPoolBalanceAfter, childPoolBalanceBefore - truncatedBridgeAmount);
        assertEq(dstUserBalanceAfter, dstUserBalanceBefore + truncatedBridgeAmount);
        assertEq(activeBalanceAfter, activeBalanceBefore - truncatedBridgeAmount);

        vm.warp(block.timestamp + 1 days);
        assertEq(
            s_childPool.getYesterdayFlow().outflow,
            flowBefore.outflow + truncatedBridgeAmount
        );
    }

    function test_handleConceroReceiveBridgeLiquidity_RevertsInvalidAmount() public {
        uint256 bridgeAmount = 2000e6;
        address dstUser = makeAddr("dstUser");

        IConceroRouter.MessageRequest memory messageRequest = _buildMessageRequest(
            BridgeCodec.encodeBridgeData(s_user, dstUser, bridgeAmount, USDC_TOKEN_DECIMALS, ""),
            PARENT_POOL_CHAIN_SELECTOR,
            address(s_parentPool)
        );

        vm.expectRevert(ICommonErrors.InvalidAmount.selector);

        vm.prank(s_conceroRouter);
        s_parentPool.conceroReceive(
            messageRequest.toMessageReceiptBytes(
                CHILD_POOL_CHAIN_SELECTOR,
                address(s_childPool),
                NONCE,
                s_internalValidatorConfigs
            ),
            s_validationChecks,
            s_validatorLibs,
            s_relayerLib
        );
    }

    function test_handleConceroReceiveBridgeLiquidity_ReorgScenario() public {
        uint256 originalAmount = 100e6;
        uint256 newAmount = 150e6;

        address dstUser = makeAddr("dstUser");

        bytes memory firstMessage = BridgeCodec.encodeBridgeData(
            s_user,
            dstUser,
            originalAmount,
            USDC_TOKEN_DECIMALS,
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
                NONCE,
                s_internalValidatorConfigs
            ),
            s_validationChecks,
            s_validatorLibs,
            s_relayerLib
        );

        bytes memory reorgMessage = BridgeCodec.encodeBridgeData(
            s_user,
            dstUser,
            newAmount,
            USDC_TOKEN_DECIMALS,
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
                NONCE,
                s_internalValidatorConfigs
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
                address(lancaClient),
                bridgeAmount,
                USDC_TOKEN_DECIMALS,
                dstCallData
            ),
            PARENT_POOL_CHAIN_SELECTOR,
            address(s_parentPool),
            dstGasLimit
        );

        vm.prank(s_conceroRouter);
        s_parentPool.conceroReceive(
            messageRequest.toMessageReceiptBytes(
                CHILD_POOL_CHAIN_SELECTOR,
                address(s_childPool),
                NONCE,
                s_internalValidatorConfigs
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
                invalidReceiver,
                bridgeAmount,
                USDC_TOKEN_DECIMALS,
                dstCallData
            ),
            PARENT_POOL_CHAIN_SELECTOR,
            address(s_parentPool),
            dstGasLimit
        );

        vm.expectRevert(ILancaBridge.InvalidConceroMessage.selector);

        vm.prank(s_conceroRouter);
        s_parentPool.conceroReceive(
            messageRequest.toMessageReceiptBytes(
                CHILD_POOL_CHAIN_SELECTOR,
                address(s_childPool),
                NONCE,
                s_internalValidatorConfigs
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
                dstUser,
                bridgeAmount,
                USDC_TOKEN_DECIMALS,
                dstCallData
            ),
            PARENT_POOL_CHAIN_SELECTOR,
            address(s_parentPool),
            dstGasLimit
        );

        vm.expectEmit(false, false, false, true);
        emit ILancaBridge.BridgeDelivered(DEFAULT_MESSAGE_ID, bridgeAmount);

        vm.prank(s_conceroRouter);
        s_parentPool.conceroReceive(
            messageRequest.toMessageReceiptBytes(
                CHILD_POOL_CHAIN_SELECTOR,
                address(s_childPool),
                NONCE,
                s_internalValidatorConfigs
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

    function test_handleConceroReceiveBridgeLiquidity_HookReverts_EmitHookCallFailed() public {
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
                address(lancaClient),
                bridgeAmount,
                USDC_TOKEN_DECIMALS,
                dstCallData
            ),
            PARENT_POOL_CHAIN_SELECTOR,
            address(s_parentPool),
            dstGasLimit
        );

        vm.expectEmit(false, true, false, true);
        emit ILancaBridge.HookCallFailed(
            DEFAULT_MESSAGE_ID,
            address(lancaClient),
            abi.encodeWithSignature("Error(string)", revertReason)
        );

        vm.expectEmit(false, false, false, true);
        emit ILancaBridge.BridgeDelivered(DEFAULT_MESSAGE_ID, bridgeAmount);

        vm.prank(s_conceroRouter);
        s_parentPool.conceroReceive(
            messageRequest.toMessageReceiptBytes(
                CHILD_POOL_CHAIN_SELECTOR,
                address(s_childPool),
                NONCE,
                s_internalValidatorConfigs
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
    }

    //    function testFuzz_receiveTokenLowerSrcDecimals(uint256 bridgeAmount) public {
    //        s_childPool = new ChildPool(
    //            s_conceroRouter,
    //            s_18DecIouToken,
    //            s_18DecUsdc,
    //            CHILD_POOL_CHAIN_SELECTOR,
    //            PARENT_POOL_CHAIN_SELECTOR
    //        );
    //
    //        uint256 userBalanceBefore = s_18DecUsdc.balanceOf(s_user);
    //
    //        _receiveBridge(s_childPool, bridgeAmount, s_user, 0);
    //    }
}
