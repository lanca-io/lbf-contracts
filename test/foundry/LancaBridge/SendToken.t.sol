// SPDX-License-Identifier: UNLICENSED
/* solhint-disable func-name-mixedcase */
pragma solidity 0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {MockConceroRouter} from "contracts/MockConceroRouter/MockConceroRouter.sol";
import {ILancaBridge} from "contracts/LancaBridge/interfaces/ILancaBridge.sol";
import {IBase} from "contracts/Base/interfaces/IBase.sol";

import {LancaBridgeBase} from "./LancaBridgeBase.sol";

import {console} from "forge-std/src/console.sol";

contract SendToken is LancaBridgeBase {
    function setUp() public override {
        super.setUp();
    }

    function test_bridge_fromParentToChildPool_Success() public {
        uint256 messageFee = parentPool.getBridgeNativeFee(CHILD_POOL_CHAIN_SELECTOR, GAS_LIMIT);

        uint256 bridgeAmount = 100e6;

        uint256 userTokenBalanceBefore = usdc.balanceOf(user);
        uint256 parentPoolBalanceBefore = usdc.balanceOf(address(parentPool));

        IBase.LiqTokenDailyFlow memory flowBefore = IBase.LiqTokenDailyFlow({
            inflow: parentPool.getYesterdayFlow().inflow,
            outflow: parentPool.getYesterdayFlow().outflow
        });
        uint256 activeBalanceBefore = parentPool.getActiveBalance();

        uint256 totalLancaFee = parentPool.getLpFee(bridgeAmount) +
            parentPool.getLancaFee(bridgeAmount) +
            parentPool.getRebalancerFee(bridgeAmount);

        bytes memory messageData = abi.encode(user, user, bridgeAmount - totalLancaFee, 0, 0, "");

        bytes32 messageId = _getMessageId(
            CHILD_POOL_CHAIN_SELECTOR,
            false,
            address(0),
            abi.encode(IBase.ConceroMessageType.BRIDGE, messageData)
        );

        vm.expectEmit(true, true, true, true);
        emit ILancaBridge.TokenSent(
            messageId,
            CHILD_POOL_CHAIN_SELECTOR,
            user,
            user,
            bridgeAmount,
            0
        );

        vm.prank(user);
        parentPool.bridge{value: messageFee}(
            user,
            bridgeAmount,
            CHILD_POOL_CHAIN_SELECTOR,
            0, // dstGasLimit for contract call
            "" // dstCallData for contract call
        );

        uint256 userTokenBalanceAfter = usdc.balanceOf(user);
        uint256 parentPoolBalanceAfter = usdc.balanceOf(address(parentPool));

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
                parentPool.getLancaFee(bridgeAmount) -
                parentPool.getRebalancerFee(bridgeAmount)
        );
    }

    function test_bridge_fromChildPoolToParentPool_Success() public {
        uint256 messageFee = parentPool.getBridgeNativeFee(PARENT_POOL_CHAIN_SELECTOR, GAS_LIMIT);

        uint256 bridgeAmount = 100e6;

        uint256 userTokenBalanceBefore = usdc.balanceOf(user);
        uint256 childPoolBalanceBefore = usdc.balanceOf(address(childPool));

        IBase.LiqTokenDailyFlow memory flowBefore = IBase.LiqTokenDailyFlow({
            inflow: childPool.getYesterdayFlow().inflow,
            outflow: childPool.getYesterdayFlow().outflow
        });
        uint256 activeBalanceBefore = childPool.getActiveBalance();

        uint256 totalLancaFee = childPool.getLpFee(bridgeAmount) +
            childPool.getLancaFee(bridgeAmount) +
            childPool.getRebalancerFee(bridgeAmount);

        bytes memory messageData = abi.encode(user, user, bridgeAmount - totalLancaFee, 0, 0, "");

        bytes32 messageId = _getMessageId(
            PARENT_POOL_CHAIN_SELECTOR,
            false,
            address(0),
            abi.encode(IBase.ConceroMessageType.BRIDGE, messageData)
        );

        vm.expectEmit(true, true, true, true);
        emit ILancaBridge.TokenSent(
            messageId,
            PARENT_POOL_CHAIN_SELECTOR,
            user,
            user,
            bridgeAmount,
            0
        );

        vm.prank(user);
        childPool.bridge{value: messageFee}(
            user,
            bridgeAmount,
            PARENT_POOL_CHAIN_SELECTOR,
            0, // dstGasLimit for contract call
            "" // dstCallData for contract call
        );

        uint256 userTokenBalanceAfter = usdc.balanceOf(user);
        uint256 childPoolBalanceAfter = usdc.balanceOf(address(childPool));

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
                childPool.getLancaFee(bridgeAmount) -
                childPool.getRebalancerFee(bridgeAmount)
        );
    }

    function test_bridge_fromChildToChildPoolWithContractCall_Success() public {
        address secondChildPool = makeAddr("secondChildPool");
        uint24 secondChildPoolChainSelector = 200;

        //        uint24[] memory dstChainSelectors = new uint24[](1);
        //        dstChainSelectors[0] = secondChildPoolChainSelector;
        //        address[] memory dstPools = new address[](1);
        //        dstPools[0] = secondChildPool;

        vm.prank(deployer);
        childPool.setDstPool(secondChildPoolChainSelector, secondChildPool);

        uint256 dstGasLimit = 200_000;
        uint256 messageFee = childPool.getBridgeNativeFee(
            secondChildPoolChainSelector,
            dstGasLimit
        );

        uint256 bridgeAmount = 100e6;
        bytes memory callData = abi.encode("test data");

        vm.prank(user);
        childPool.bridge{value: messageFee}(
            user,
            bridgeAmount,
            secondChildPoolChainSelector,
            dstGasLimit, // dstGasLimit for contract call
            callData // dstCallData for contract call
        );
    }

    function test_bridge_revertIfInvalidDstGasLimitOrCallData() public {
        vm.expectRevert(abi.encodeWithSelector(ILancaBridge.InvalidDstGasLimitOrCallData.selector));

        bytes memory nonZeroBytes = "0x01";

        vm.prank(user);
        childPool.bridge{value: 0}(user, 100e6, PARENT_POOL_CHAIN_SELECTOR, 0, nonZeroBytes);

        uint256 nonZeroGasLimit = GAS_LIMIT;

        vm.expectRevert(abi.encodeWithSelector(ILancaBridge.InvalidDstGasLimitOrCallData.selector));

        vm.prank(user);
        childPool.bridge{value: 0}(user, 100e6, PARENT_POOL_CHAIN_SELECTOR, nonZeroGasLimit, "");
    }
}
