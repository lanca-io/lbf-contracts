// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {ParentPoolBase} from "../ParentPool/ParentPoolBase.sol";
import {IBase} from "../../../contracts/Base/interfaces/IBase.sol";

contract Rebalancer is ParentPoolBase {
    function setUp() public override {
        super.setUp();
    }

    function test_filDeficitAndSendBridgeIou(
        uint256 parentPoolBaseBalance,
        uint256 deficit
    ) public {
        vm.assume(parentPoolBaseBalance > 0 && parentPoolBaseBalance < MAX_DEPOSIT_AMOUNT);
        vm.assume(deficit > 0 && deficit < parentPoolBaseBalance && deficit < MAX_DEPOSIT_AMOUNT);

        _mintUsdc(address(s_parentPool), parentPoolBaseBalance);
        _mintUsdc(user, deficit);
        s_parentPool.exposed_setTargetBalance(parentPoolBaseBalance + deficit);

        uint256 iouBalanceBefore = iouToken.balanceOf(user);
        vm.prank(user);
        s_parentPool.fillDeficit(deficit);
        uint256 iouBalanceAfter = iouToken.balanceOf(user);

        assertEq(iouBalanceAfter - iouBalanceBefore, deficit);

        uint24 dstChainSelector = childPoolChainSelector_1;
        uint256 iouTotalSupplyBefore = iouToken.totalSupply();
        iouBalanceBefore = iouToken.balanceOf(user);
        vm.startPrank(user);
        iouToken.approve(address(s_parentPool), deficit);
        s_parentPool.bridgeIOU{value: s_parentPool.getBridgeIouNativeFee(dstChainSelector)}(
            deficit,
            dstChainSelector
        );
        vm.stopPrank();
        iouBalanceAfter = iouToken.balanceOf(user);
        uint256 iouTotalSupplyAfter = iouToken.totalSupply();

        assertEq(iouBalanceBefore - iouBalanceAfter, deficit);
        assertEq(iouTotalSupplyBefore - iouTotalSupplyAfter, deficit);
    }

    function test_receiveBridgeIouAndTakeSurplus(
        uint256 parentPoolBaseBalance,
        uint256 surplusToTake
    ) public {
        vm.assume(parentPoolBaseBalance > 0 && parentPoolBaseBalance < MAX_DEPOSIT_AMOUNT);
        vm.assume(
            surplusToTake > 0 &&
                surplusToTake < parentPoolBaseBalance &&
                surplusToTake < MAX_DEPOSIT_AMOUNT
        );

        _mintUsdc(
            address(s_parentPool),
            parentPoolBaseBalance + s_parentPool.getRebalancerFee(surplusToTake)
        );
        _mintUsdc(user, surplusToTake);
        s_parentPool.exposed_setTargetBalance(parentPoolBaseBalance - surplusToTake);
        s_parentPool.exposed_setTotalRebalancerFee(s_parentPool.getRebalancerFee(surplusToTake));

        uint256 iouBalanceBefore = iouToken.balanceOf(user);

        vm.prank(s_parentPool.exposed_getConceroRouter());
        s_parentPool.conceroReceive(
            keccak256("conceroMessageId"),
            childPoolChainSelector_1,
            abi.encode(s_childPool_1),
            abi.encode(IBase.ConceroMessageType.BRIDGE_IOU, abi.encode(surplusToTake, user))
        );

        uint256 iouBalanceAfter = iouToken.balanceOf(user);

        assertEq(iouBalanceAfter - iouBalanceBefore, surplusToTake);

        uint256 usdcBalanceBefore = usdc.balanceOf(user);
        vm.startPrank(user);
        iouToken.approve(address(s_parentPool), surplusToTake);
        s_parentPool.takeSurplus(surplusToTake);
        vm.stopPrank();
        uint256 usdcBalanceAfter = usdc.balanceOf(user);

        assertEq(
            usdcBalanceAfter - usdcBalanceBefore,
            surplusToTake + s_parentPool.getRebalancerFee(surplusToTake)
        );
    }
}
