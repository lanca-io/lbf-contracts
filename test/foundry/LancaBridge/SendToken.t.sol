// SPDX-License-Identifier: UNLICENSED
/* solhint-disable func-name-mixedcase */
pragma solidity 0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {ConceroTypes} from "@concero/v2-contracts/contracts/interfaces/IConceroRouter.sol";

import {CommonTypes} from "contracts/common/CommonTypes.sol";
import {MockConceroRouter} from "contracts/MockConceroRouter/MockConceroRouter.sol";
import {ILancaBridge} from "contracts/LancaBridge/interfaces/ILancaBridge.sol";
import {IPoolBase} from "contracts/PoolBase/interfaces/IPoolBase.sol";

import {LancaBridgeBase} from "./LancaBridgeBase.sol";

contract SendToken is LancaBridgeBase {
    function setUp() public override {
        super.setUp();
    }

    function test_bridge_fromParentToChildPool_Success() public {
        uint256 messageFee = parentPool.getMessageFee(
            CHILD_POOL_CHAIN_SELECTOR,
            address(childPool),
            GAS_LIMIT
        );

        uint256 bridgeAmount = 100e6;

        uint256 userTokenBalanceBefore = IERC20(usdc).balanceOf(user);
        uint256 parentPoolBalanceBefore = IERC20(usdc).balanceOf(address(parentPool));

        IPoolBase.LiqTokenDailyFlow memory flowBefore = IPoolBase.LiqTokenDailyFlow({
            inflow: parentPool.getYesterdayFlow().inflow,
            outflow: parentPool.getYesterdayFlow().outflow
        });
        uint256 activeBalanceBefore = parentPool.getActiveBalance();

        uint256 totalLancaFee = parentPool.getLpFee(bridgeAmount) +
            parentPool.getBridgeFee(bridgeAmount) +
            parentPool.getRebalancerFee(bridgeAmount);

        vm.expectEmit(true, true, true, true);
        emit ILancaBridge.TokenSent(
            bytes32(uint256(1)),
            CHILD_POOL_CHAIN_SELECTOR,
            usdc,
            user,
            user,
            bridgeAmount - totalLancaFee,
            address(childPool)
        );

        vm.prank(user);
        parentPool.bridge{value: messageFee}(
            usdc,
            user,
            bridgeAmount,
            CHILD_POOL_CHAIN_SELECTOR,
            false, // isTokenReceiverContract
            0, // dstGasLimit for contract call
            "" // dstCallData for contract call
        );

        uint256 userTokenBalanceAfter = IERC20(usdc).balanceOf(user);
        uint256 parentPoolBalanceAfter = IERC20(usdc).balanceOf(address(parentPool));

        assertEq(userTokenBalanceAfter, userTokenBalanceBefore - bridgeAmount);
        assertEq(parentPoolBalanceAfter, parentPoolBalanceBefore + bridgeAmount);

        vm.warp(block.timestamp + 1 days);
        assertEq(
            parentPool.getYesterdayFlow().inflow,
            flowBefore.inflow + (bridgeAmount - totalLancaFee)
        );

        uint256 activeBalanceAfter = parentPool.getActiveBalance();
        assertEq(
            activeBalanceAfter,
            activeBalanceBefore +
                bridgeAmount -
                parentPool.getBridgeFee(bridgeAmount) -
                parentPool.getRebalancerFee(bridgeAmount)
        );
    }

    function test_bridge_fromChildPoolToParentPool_Success() public {
        uint256 messageFee = parentPool.getMessageFee(
            PARENT_POOL_CHAIN_SELECTOR,
            address(parentPool),
            GAS_LIMIT
        );

        uint256 bridgeAmount = 100e6;

        uint256 userTokenBalanceBefore = IERC20(usdc).balanceOf(user);
        uint256 childPoolBalanceBefore = IERC20(usdc).balanceOf(address(childPool));

        IPoolBase.LiqTokenDailyFlow memory flowBefore = IPoolBase.LiqTokenDailyFlow({
            inflow: childPool.getYesterdayFlow().inflow,
            outflow: childPool.getYesterdayFlow().outflow
        });
        uint256 activeBalanceBefore = childPool.getActiveBalance();

        uint256 totalLancaFee = childPool.getLpFee(bridgeAmount) +
            childPool.getBridgeFee(bridgeAmount) +
            childPool.getRebalancerFee(bridgeAmount);

        vm.expectEmit(true, true, true, true);
        emit ILancaBridge.TokenSent(
            bytes32(uint256(1)),
            PARENT_POOL_CHAIN_SELECTOR,
            usdc,
            user,
            user,
            bridgeAmount - totalLancaFee,
            address(parentPool)
        );

        vm.prank(user);
        childPool.bridge{value: messageFee}(
            usdc,
            user,
            bridgeAmount,
            PARENT_POOL_CHAIN_SELECTOR,
            false, // isTokenReceiverContract
            GAS_LIMIT, // dstGasLimit for contract call
            "" // dstCallData for contract call
        );

        uint256 userTokenBalanceAfter = IERC20(usdc).balanceOf(user);
        uint256 childPoolBalanceAfter = IERC20(usdc).balanceOf(address(childPool));

        assertEq(userTokenBalanceAfter, userTokenBalanceBefore - bridgeAmount);
        assertEq(childPoolBalanceAfter, childPoolBalanceBefore + bridgeAmount);

        vm.warp(block.timestamp + 1 days);
        assertEq(
            childPool.getYesterdayFlow().inflow,
            flowBefore.inflow + (bridgeAmount - totalLancaFee)
        );

        uint256 activeBalanceAfter = childPool.getActiveBalance();
        assertEq(
            activeBalanceAfter,
            activeBalanceBefore +
                bridgeAmount -
                childPool.getBridgeFee(bridgeAmount) -
                childPool.getRebalancerFee(bridgeAmount)
        );
    }

    function test_bridge_fromChildToChildPoolWithContractCall_Success() public {
        address secondChildPool = makeAddr("secondChildPool");
        uint24 secondChildPoolChainSelector = 200;

        uint24[] memory dstChainSelectors = new uint24[](1);
        dstChainSelectors[0] = secondChildPoolChainSelector;
        address[] memory dstPools = new address[](1);
        dstPools[0] = secondChildPool;

        vm.prank(deployer);
        childPool.addDstPools(dstChainSelectors, dstPools);

        uint256 dstGasLimit = 200_000;
        uint256 messageFee = childPool.getMessageFee(
            secondChildPoolChainSelector,
            secondChildPool,
            dstGasLimit
        );

        uint256 bridgeAmount = 100e6;
        bytes memory callData = abi.encode("test data");

        vm.prank(user);
        childPool.bridge{value: messageFee}(
            usdc,
            user,
            bridgeAmount,
            secondChildPoolChainSelector,
            true, // isTokenReceiverContract
            dstGasLimit, // dstGasLimit for contract call
            callData // dstCallData for contract call
        );

        assertEq(MockConceroRouter(conceroRouter).dstChainSelector(), secondChildPoolChainSelector);
        assertEq(MockConceroRouter(conceroRouter).shouldFinaliseSrc(), false);
        assertEq(MockConceroRouter(conceroRouter).feeToken(), address(0));

        (CommonTypes.MessageType messageType, bytes memory messageData) = abi.decode(
            MockConceroRouter(conceroRouter).message(),
            (CommonTypes.MessageType, bytes)
        );

        assertEq(uint8(messageType), uint8(CommonTypes.MessageType.BRIDGE_LIQUIDITY));

        (CommonTypes.BridgeType bridgeType, bytes memory bridgeData) = abi.decode(
            messageData,
            (CommonTypes.BridgeType, bytes)
        );

        assertEq(uint8(bridgeType), uint8(CommonTypes.BridgeType.CONTRACT_TRANSFER));

        (
            address token,
            address tokenSender,
            address tokenReceiver,
            uint256 tokenAmount,
            bytes memory dstCallData
        ) = abi.decode(bridgeData, (address, address, address, uint256, bytes));

        assertEq(token, usdc);
        assertEq(tokenSender, user);
        assertEq(tokenReceiver, user);
        assertEq(tokenAmount, bridgeAmount - 70000); // 70000 is the total fee
        assertEq(dstCallData, callData);
    }
}
