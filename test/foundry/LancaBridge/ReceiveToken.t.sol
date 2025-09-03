// SPDX-License-Identifier: UNLICENSED
/* solhint-disable func-name-mixedcase */
pragma solidity 0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {IBase} from "contracts/Base/interfaces/IBase.sol";
import {ILancaBridge} from "contracts/LancaBridge/interfaces/ILancaBridge.sol";

import {LancaBridgeBase} from "./LancaBridgeBase.sol";

contract ReceiveToken is LancaBridgeBase {
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

        vm.expectEmit(true, true, true, true);
        emit ILancaBridge.BridgeDelivered(DEFAULT_MESSAGE_ID, bridgeAmount);

        vm.prank(conceroRouter);
        parentPool.conceroReceive(
            DEFAULT_MESSAGE_ID,
            CHILD_POOL_CHAIN_SELECTOR,
            abi.encode(address(childPool)),
            message
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

        vm.expectEmit(true, true, true, true);
        emit ILancaBridge.BridgeDelivered(DEFAULT_MESSAGE_ID, bridgeAmount);

        vm.prank(conceroRouter);
        childPool.conceroReceive(
            DEFAULT_MESSAGE_ID,
            PARENT_POOL_CHAIN_SELECTOR,
            abi.encode(address(parentPool)),
            message
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
}
