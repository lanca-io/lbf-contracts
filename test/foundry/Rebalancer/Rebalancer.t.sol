// SPDX-License-Identifier: UNLICENSED
/* solhint-disable func-name-mixedcase */
pragma solidity 0.8.28;

import {IBase} from "contracts/Base/interfaces/IBase.sol";
import {ICommonErrors} from "contracts/common/interfaces/ICommonErrors.sol";
import {IRebalancer} from "contracts/Rebalancer/interfaces/IRebalancer.sol";

import {MockERC20} from "../scripts/deploy/DeployMockERC20.s.sol";
import {ParentPoolBase} from "../ParentPool/ParentPoolBase.sol";

contract Rebalancer is ParentPoolBase {
    function setUp() public override {
        super.setUp();
        vm.warp(NOW_TIMESTAMP);
    }

    function test_fillDeficitAndSendBridgeIou(
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

    /* -- Post inflow rebalance -- */

    /*
     * @dev totalWithdrawalAmountLocked should be 0 when active balance
     * less than targetBalanceFloor
     */
    function test_postInflowRebalance_totalWithdrawalAmountLockedShouldBeZero() public {
        _baseSetupWithLPMinting();

        address user1 = _getUsers(1)[0];
        uint256 usdcBalanceBefore = usdc.balanceOf(user1);
        _enterWithdrawalQueue(user1, _takeRebalancerFee(_addDecimals(2_000)));

        // Imagine that someone send 1000 USDC from ParentPool to ChildPool
        _fillChildPoolSnapshots(_addDecimals(1_000));
        MockERC20(address(usdc)).burn(address(s_parentPool), _addDecimals(1_000));
        s_parentPool.exposed_setChildPoolSnapshot(
            1,
            _getChildPoolSnapshot(_addDecimals(2_000), 0, 0)
        );
        assertEq(usdc.balanceOf(address(s_parentPool)), 0);

        // Re-calculate target balances
        _triggerDepositWithdrawProcess();
        assertEq(s_parentPool.getDeficit(), _addDecimals(2800));

        // Now we have an initial target balance for all pools of about 800 USDC
        // and a deficit of 2800 USDC
        //		- parent pool balance is 0
        //		- withdrawal amount is 2000 USDC
        //		- new target balance is 800 USDC

        // Fill the deficit with 100 USDC to trigger postInflowRebalance
        _fillDeficit(_addDecimals(100));

        // Check that totalWithdrawalAmountLocked is 0
        assertEq(s_parentPool.exposed_getTotalWithdrawalAmountLocked(), 0);
        assertFalse(s_parentPool.isReadyToProcessPendingWithdrawals());

        // Fill full deficit (2700 USDC)
        _fillDeficit(s_parentPool.getDeficit());

        // Now we can withdraw 2000 USDC
        _processPendingWithdrawals();

        // 800 USDC should be in the ParentPool
        assertApproxEqRel(usdc.balanceOf(address(s_parentPool)), _addDecimals(800), 1e15);

        // User1 should have 2000 USDC
        assertEq(
            usdc.balanceOf(user1),
            usdcBalanceBefore + _takeRebalancerFee(_addDecimals(2_000))
        );
    }

    function test_fillDeficit_RevertsIfAmountIsZero() public {
        vm.expectRevert(ICommonErrors.AmountIsZero.selector);
        s_parentPool.fillDeficit(0);
    }

    function test_fillDeficit_RevertsIfAmountExceedsDeficit() public {
        vm.expectRevert(abi.encodeWithSelector(IRebalancer.AmountExceedsDeficit.selector, 0, 1));

        s_parentPool.fillDeficit(1);
    }

    function test_takeSurplus_RevertsIfAmountIsZero() public {
        vm.expectRevert(ICommonErrors.AmountIsZero.selector);
        s_parentPool.takeSurplus(0);
    }

    function test_takeSurplus_RevertsIfAmountExceedsSurplus() public {
        vm.expectRevert(abi.encodeWithSelector(IRebalancer.AmountExceedsSurplus.selector, 0, 1));
        s_parentPool.takeSurplus(1);
    }

    function test_takeSurplus_RevertsIfInsufficientRebalancingFee() public {
        _baseSetupWithLPMinting();

        uint256 amountToRebalance = _addDecimals(900);
        uint256 rebalancerFee = s_parentPool.getRebalancerFee(amountToRebalance);

        s_parentPool.exposed_setTargetBalance(_addDecimals(100));
        assertEq(s_parentPool.getSurplus(), amountToRebalance);

        vm.prank(address(s_parentPool));
        iouToken.mint(user, amountToRebalance);

        vm.startPrank(user);
        iouToken.approve(address(s_parentPool), amountToRebalance);

        vm.expectRevert(
            abi.encodeWithSelector(
                IRebalancer.InsufficientRebalancingFee.selector,
                0,
                rebalancerFee
            )
        );

        s_parentPool.takeSurplus(_addDecimals(900));
        vm.stopPrank();
    }

    function test_bridgeIOU_RevertsIfAmountIsZero() public {
        vm.expectRevert(ICommonErrors.AmountIsZero.selector);
        s_parentPool.bridgeIOU(0, 1);
    }

    function test_bridgeIOU_RevertsIfInvalidDestinationChain() public {
        vm.expectRevert(IRebalancer.InvalidDestinationChain.selector);
        s_parentPool.bridgeIOU(1, 5);
    }

    function test_getIouToken() public view {
        assertEq(s_parentPool.getIOUToken(), address(iouToken));
    }
}
