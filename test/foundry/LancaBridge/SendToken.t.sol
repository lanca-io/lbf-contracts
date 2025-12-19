// SPDX-License-Identifier: UNLICENSED
/* solhint-disable func-name-mixedcase */
pragma solidity 0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ConceroRouterMock} from "../mocks/ConceroRouterMock.sol";
import {ILancaBridge} from "contracts/LancaBridge/interfaces/ILancaBridge.sol";
import {IBase} from "contracts/Base/interfaces/IBase.sol";
import {MessageCodec} from "@concero/v2-contracts/contracts/common/libraries/MessageCodec.sol";
import {LancaBridgeBase} from "./LancaBridgeBase.sol";
import {BridgeCodec} from "contracts/common/libraries/BridgeCodec.sol";

contract SendToken is LancaBridgeBase {
    using BridgeCodec for address;

    function test_bridge_fromParentToChildPool_gas() public {
        vm.pauseGasMetering();

        bytes memory dstChainData = MessageCodec.encodeEvmDstChainData(s_user, 0);
        uint256 bridgeAmount = 100e6;

        uint256 messageFee = s_parentPool.getBridgeNativeFee(
            bridgeAmount,
            CHILD_POOL_CHAIN_SELECTOR,
            dstChainData,
            ""
        );

        vm.prank(s_user);
        vm.resumeGasMetering();
        s_parentPool.bridge{value: messageFee}(
            bridgeAmount,
            CHILD_POOL_CHAIN_SELECTOR,
            dstChainData,
            ""
        );
    }

    function test_bridge_fromChildPoolToParentPool_gas() public {
        vm.pauseGasMetering();

        bytes memory dstChainData = MessageCodec.encodeEvmDstChainData(s_user, 0);
        uint256 bridgeAmount = 100e6;

        uint256 messageFee = s_childPool.getBridgeNativeFee(
            bridgeAmount,
            PARENT_POOL_CHAIN_SELECTOR,
            dstChainData,
            ""
        );

        vm.prank(s_user);
        vm.resumeGasMetering();
        s_childPool.bridge{value: messageFee}(
            bridgeAmount,
            PARENT_POOL_CHAIN_SELECTOR,
            dstChainData,
            ""
        );
    }

    function test_bridge_fromParentToChildPool_Success() public {
        bytes memory dstChainData = MessageCodec.encodeEvmDstChainData(s_user, 0);
        uint256 bridgeAmount = 100e6;

        uint256 messageFee = s_parentPool.getBridgeNativeFee(
            bridgeAmount,
            CHILD_POOL_CHAIN_SELECTOR,
            dstChainData,
            ""
        );

        uint256 userTokenBalanceBefore = s_usdc.balanceOf(s_user);
        uint256 parentPoolBalanceBefore = s_usdc.balanceOf(address(s_parentPool));

        IBase.LiqTokenDailyFlow memory flowBefore = IBase.LiqTokenDailyFlow({
            inflow: s_parentPool.getYesterdayFlow().inflow,
            outflow: s_parentPool.getYesterdayFlow().outflow
        });
        uint256 activeBalanceBefore = s_parentPool.getActiveBalance();

        uint256 totalLancaFee = s_parentPool.getLpFee(bridgeAmount) +
            s_parentPool.getLancaFee(bridgeAmount) +
            s_parentPool.getRebalancerFee(bridgeAmount);

        vm.expectEmit(false, true, true, true);
        emit ILancaBridge.BridgeSent(
            DEFAULT_MESSAGE_ID,
            CHILD_POOL_CHAIN_SELECTOR,
            dstChainData,
            s_user,
            bridgeAmount
        );

        vm.prank(s_user);
        s_parentPool.bridge{value: messageFee}(
            bridgeAmount,
            CHILD_POOL_CHAIN_SELECTOR,
            dstChainData,
            ""
        );

        uint256 userTokenBalanceAfter = s_usdc.balanceOf(s_user);
        uint256 parentPoolBalanceAfter = s_usdc.balanceOf(address(s_parentPool));

        assertEq(userTokenBalanceAfter, userTokenBalanceBefore - bridgeAmount);
        assertEq(parentPoolBalanceAfter, parentPoolBalanceBefore + bridgeAmount);

        vm.warp(block.timestamp + 1 days);
        assertEq(
            s_parentPool.getYesterdayFlow().inflow,
            flowBefore.inflow + (bridgeAmount - totalLancaFee)
        );

        uint256 activeBalanceAfter = s_parentPool.getActiveBalance();
        assertApproxEqRel(
            activeBalanceAfter,
            activeBalanceBefore +
                bridgeAmount -
                s_parentPool.getLancaFee(bridgeAmount) -
                s_parentPool.getRebalancerFee(bridgeAmount),
            1e15
        );
    }

    function testFuzz_bridge_fromChildPoolToParentPool_Success(uint128 bridgeAmount) public {
        deal(address(s_18DecUsdc), address(s_user), bridgeAmount);

        bytes memory dstChainData = MessageCodec.encodeEvmDstChainData(s_user, 0);

        uint256 messageFee = s_childPool.getBridgeNativeFee(
            bridgeAmount,
            PARENT_POOL_CHAIN_SELECTOR,
            dstChainData,
            ""
        );

        uint256 userTokenBalanceBefore = s_18DecUsdc.balanceOf(s_user);
        uint256 childPoolBalanceBefore = s_18DecUsdc.balanceOf(address(s_childPool));

        IBase.LiqTokenDailyFlow memory flowBefore = IBase.LiqTokenDailyFlow({
            inflow: s_childPool.getYesterdayFlow().inflow,
            outflow: s_childPool.getYesterdayFlow().outflow
        });
        uint256 activeBalanceBefore = s_childPool.getActiveBalance();

        uint256 totalLancaFee = s_childPool.getLpFee(bridgeAmount) +
            s_childPool.getLancaFee(bridgeAmount) +
            s_childPool.getRebalancerFee(bridgeAmount);

        vm.expectEmit(false, true, true, true);
        emit ILancaBridge.BridgeSent(
            DEFAULT_MESSAGE_ID,
            PARENT_POOL_CHAIN_SELECTOR,
            dstChainData,
            s_user,
            bridgeAmount
        );

        vm.prank(s_user);
        s_childPool.bridge{value: messageFee}(
            bridgeAmount,
            PARENT_POOL_CHAIN_SELECTOR,
            dstChainData,
            ""
        );

        uint256 userTokenBalanceAfter = s_18DecUsdc.balanceOf(s_user);
        uint256 childPoolBalanceAfter = s_18DecUsdc.balanceOf(address(s_childPool));

        assertEq(userTokenBalanceAfter, userTokenBalanceBefore - bridgeAmount);
        assertEq(childPoolBalanceAfter, childPoolBalanceBefore + bridgeAmount);

        vm.warp(block.timestamp + 1 days);
        assertEq(
            s_childPool.getYesterdayFlow().inflow,
            flowBefore.inflow + (bridgeAmount - totalLancaFee)
        );

        uint256 activeBalanceAfter = s_childPool.getActiveBalance();
        assertApproxEqRel(
            activeBalanceAfter,
            activeBalanceBefore +
                bridgeAmount -
                s_childPool.getLancaFee(bridgeAmount) -
                s_childPool.getRebalancerFee(bridgeAmount),
            1e10
        ); // max delta: 0.000001
    }

    function test_bridge_fromChildToChildPoolWithContractCall_Success() public {
        address secondChildPool = makeAddr("secondChildPool");
        uint24 secondChildPoolChainSelector = 200;
        uint32 dstGasLimit = 200_000;
        uint256 bridgeAmount = 100e6;

        bytes memory dstChainData = MessageCodec.encodeEvmDstChainData(s_user, dstGasLimit);

        vm.prank(s_deployer);
        s_childPool.setDstPool(secondChildPoolChainSelector, secondChildPool.toBytes32());

        bytes memory callData = abi.encode("test data");

        uint256 messageFee = s_childPool.getBridgeNativeFee(
            bridgeAmount,
            secondChildPoolChainSelector,
            dstChainData,
            callData
        );

        vm.prank(s_user);
        s_childPool.bridge{value: messageFee}(
            bridgeAmount,
            secondChildPoolChainSelector,
            dstChainData,
            callData
        );
    }

    function test_withdrawLancaFee_RevertIfNotAdmin() public {
        vm.expectRevert();

        vm.prank(s_user);
        s_childPool.withdrawLancaFee(100e6);
    }

    function test_withdrawLancaFee_Success() public {
        vm.prank(s_deployer);
        s_childPool.setLancaBridgeFeeBps(100);

        test_bridge_fromChildToChildPoolWithContractCall_Success();

        uint256 bridgeAmount = 100e6;
        uint256 totalLancaFee = s_childPool.getLancaFee(bridgeAmount);
        assert(totalLancaFee > 0);

        vm.expectEmit(true, true, false, true);
        emit IBase.LancaFeeWithdrawn(s_deployer, totalLancaFee);

        vm.prank(s_deployer);
        s_childPool.withdrawLancaFee(totalLancaFee);
    }

    function test_bridge_revertIfInvalidDstGasLimitOrCallData() public {
        vm.expectRevert(abi.encodeWithSelector(ILancaBridge.InvalidDstGasLimitOrCallData.selector));

        bytes memory nonZeroBytes = "0x01";
        bytes memory dstChainData = MessageCodec.encodeEvmDstChainData(s_user, 0);

        vm.prank(s_user);
        s_childPool.bridge{value: 0}(1, PARENT_POOL_CHAIN_SELECTOR, dstChainData, nonZeroBytes);

        dstChainData = MessageCodec.encodeEvmDstChainData(s_user, GAS_LIMIT); // nonZeroGasLimit

        vm.expectRevert(abi.encodeWithSelector(ILancaBridge.InvalidDstGasLimitOrCallData.selector));

        vm.prank(s_user);
        s_childPool.bridge{value: 0}(1, PARENT_POOL_CHAIN_SELECTOR, dstChainData, "");
    }

    function test_bridge_revertIfInvalidDstChainSelector() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                ILancaBridge.InvalidDstChainSelector.selector,
                CHILD_POOL_CHAIN_SELECTOR
            )
        );
        bytes memory dstChainData = MessageCodec.encodeEvmDstChainData(s_user, 0);

        vm.prank(s_user);
        s_childPool.bridge{value: 0.0001 ether}(1, CHILD_POOL_CHAIN_SELECTOR, dstChainData, "");
    }
}
