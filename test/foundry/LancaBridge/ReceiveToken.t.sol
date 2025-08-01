// SPDX-License-Identifier: UNLICENSED
/* solhint-disable func-name-mixedcase */
pragma solidity 0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {CommonTypes} from "contracts/common/CommonTypes.sol";
import {IPoolBase} from "contracts/PoolBase/interfaces/IPoolBase.sol";
import {ILancaBridge} from "contracts/LancaBridge/interfaces/ILancaBridge.sol";

import {LancaBridgeBase} from "./LancaBridgeBase.sol";

contract ReceiveToken is LancaBridgeBase {
    function setUp() public override {
        super.setUp();

        deal(usdc, address(parentPool), 1000e6);
        deal(usdc, address(childPool), 1000e6);
    }

    function test_ReceiveTokenToParentPool_Success() public {
        uint256 bridgeAmount = 100e6;
        address dstUser = makeAddr("dstUser");

        bytes memory message = _encodeBridgeMessage(
            CommonTypes.MessageType.BRIDGE_LIQUIDITY,
            CommonTypes.BridgeType.EOA_TRANSFER,
            abi.encode(usdc, user, dstUser, bridgeAmount)
        );

        uint256 parentPoolBalanceBefore = IERC20(usdc).balanceOf(address(parentPool));
        uint256 dstUserBalanceBefore = IERC20(usdc).balanceOf(dstUser);
        uint256 activeBalanceBefore = parentPool.getActiveBalance();
        IPoolBase.LiqTokenDailyFlow memory flowBefore = IPoolBase.LiqTokenDailyFlow({
            inflow: parentPool.getYesterdayFlow().inflow,
            outflow: parentPool.getYesterdayFlow().outflow
        });

        vm.expectEmit(true, true, true, true);
        emit ILancaBridge.BridgeDelivered(
            DEFAULT_MESSAGE_ID,
            CHILD_POOL_CHAIN_SELECTOR,
            usdc,
            user,
            dstUser,
            bridgeAmount
        );

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

        bytes memory message = _encodeBridgeMessage(
            CommonTypes.MessageType.BRIDGE_LIQUIDITY,
            CommonTypes.BridgeType.EOA_TRANSFER,
            abi.encode(usdc, user, dstUser, bridgeAmount)
        );

        uint256 childPoolBalanceBefore = IERC20(usdc).balanceOf(address(childPool));
        uint256 dstUserBalanceBefore = IERC20(usdc).balanceOf(dstUser);
        uint256 activeBalanceBefore = childPool.getActiveBalance();
        IPoolBase.LiqTokenDailyFlow memory flowBefore = IPoolBase.LiqTokenDailyFlow({
            inflow: childPool.getYesterdayFlow().inflow,
            outflow: childPool.getYesterdayFlow().outflow
        });

        vm.expectEmit(true, true, true, true);
        emit ILancaBridge.BridgeDelivered(
            DEFAULT_MESSAGE_ID,
            PARENT_POOL_CHAIN_SELECTOR,
            usdc,
            user,
            dstUser,
            bridgeAmount
        );

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

    function _encodeBridgeMessage(
        CommonTypes.MessageType messageType,
        CommonTypes.BridgeType bridgeType,
        bytes memory bridgeData
    ) internal pure returns (bytes memory) {
        bytes memory messageData = abi.encode(bridgeType, bridgeData);
        return abi.encode(messageType, messageData);
    }
}
