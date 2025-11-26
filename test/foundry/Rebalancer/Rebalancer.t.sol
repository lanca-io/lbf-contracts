// SPDX-License-Identifier: UNLICENSED
/* solhint-disable func-name-mixedcase */
pragma solidity 0.8.28;

import {IConceroRouter} from "@concero/v2-contracts/contracts/interfaces/IConceroRouter.sol";
import {MessageCodec} from "@concero/v2-contracts/contracts/common/libraries/MessageCodec.sol";
import {IBase} from "contracts/Base/interfaces/IBase.sol";
import {ICommonErrors} from "contracts/common/interfaces/ICommonErrors.sol";
import {IRebalancer} from "contracts/Rebalancer/interfaces/IRebalancer.sol";
import {ChildPool} from "contracts/ChildPool/ChildPool.sol";
import {RebalancerBase} from "../Rebalancer/RebalancerBase.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {BridgeCodec} from "contracts/common/libraries/BridgeCodec.sol";

contract Rebalancer is RebalancerBase {
    using MessageCodec for IConceroRouter.MessageRequest;
    using BridgeCodec for address;

    function setUp() public override {
        super.setUp();
        vm.warp(NOW_TIMESTAMP);
    }

    function testFuzz_fillDeficitAndSendBridgeIou(
        uint256 parentPoolBaseBalance,
        uint256 deficit
    ) public {
        _setSupportedChildPools(9);

        vm.assume(parentPoolBaseBalance > 0 && parentPoolBaseBalance < MAX_DEPOSIT_AMOUNT);
        vm.assume(deficit > 0 && deficit < parentPoolBaseBalance && deficit < MAX_DEPOSIT_AMOUNT);

        _mintUsdc(address(s_parentPool), parentPoolBaseBalance);
        _mintUsdc(address(s_operator), deficit);

        s_parentPool.exposed_setTargetBalance(parentPoolBaseBalance + deficit);

        uint256 iouBalanceBefore = s_iouToken.balanceOf(s_operator);
        _fillDeficit(deficit);
        uint256 iouBalanceAfter = s_iouToken.balanceOf(s_operator);

        assertEq(iouBalanceAfter - iouBalanceBefore, deficit);

        uint24 dstChainSelector = childPoolChainSelector_1;
        uint256 iouTotalSupplyBefore = s_iouToken.totalSupply();

        iouBalanceBefore = s_iouToken.balanceOf(s_operator);

        vm.startPrank(s_operator);
        s_iouToken.approve(address(s_parentPool), deficit);
        s_parentPool.bridgeIOU{value: s_parentPool.getBridgeIouNativeFee(dstChainSelector)}(
            s_operator.toBytes32(),
            dstChainSelector,
            deficit
        );
        vm.stopPrank();

        iouBalanceAfter = s_iouToken.balanceOf(s_operator);
        uint256 iouTotalSupplyAfter = s_iouToken.totalSupply();

        assertEq(iouBalanceBefore - iouBalanceAfter, 0);
        assertEq(iouTotalSupplyBefore - iouTotalSupplyAfter, 0);
    }

    function testFuzz_receiveBridgeIouAndTakeSurplus(
        uint256 parentPoolBaseBalance,
        uint256 surplusToTake
    ) public {
        _setSupportedChildPools(9);

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
        _mintUsdc(s_user, surplusToTake);
        s_parentPool.exposed_setTargetBalance(parentPoolBaseBalance - surplusToTake);

        uint256 iouBalanceBefore = s_iouToken.balanceOf(s_user);

        IConceroRouter.MessageRequest memory messageRequest = _buildMessageRequest(
            BridgeCodec.encodeBridgeIouData(s_user.toBytes32(), surplusToTake, USDC_TOKEN_DECIMALS),
            PARENT_POOL_CHAIN_SELECTOR,
            address(s_parentPool)
        );

        vm.prank(s_parentPool.exposed_getConceroRouter());
        s_parentPool.conceroReceive(
            messageRequest.toMessageReceiptBytes(
                childPoolChainSelector_1,
                address(s_childPool_1),
                NONCE
            ),
            s_validationChecks,
            s_validatorLibs,
            s_relayerLib
        );

        uint256 iouBalanceAfter = s_iouToken.balanceOf(s_user);

        assertEq(iouBalanceAfter - iouBalanceBefore, surplusToTake);

        uint256 usdcBalanceBefore = s_usdc.balanceOf(s_user);
        vm.startPrank(s_user);
        s_iouToken.approve(address(s_parentPool), surplusToTake);
        s_parentPool.takeSurplus(surplusToTake);
        vm.stopPrank();
        uint256 usdcBalanceAfter = s_usdc.balanceOf(s_user);

        assertEq(usdcBalanceAfter - usdcBalanceBefore, surplusToTake);
    }

    // /* -- Rebalancer fee -- */

    function test_RebalancerFee_CalculatesCorrectlyWhenDepositToEmptyPool() public {
        _setSupportedChildPools(2); // 2 child pools

        vm.prank(s_deployer);
        s_parentPool.setLiquidityCap(_addDecimals(3_000));

        _setQueuesLength(0, 0);
        _enterDepositQueue(s_user, _addDecimals(3_000));

        _fillChildPoolSnapshots();
        _triggerDepositWithdrawProcess();

        assertEq(s_parentPool.getTargetBalance(), _takeRebalancerFee(_addDecimals(1_000)));
        assertEq(s_childPool_1.getTargetBalance(), _takeRebalancerFee(_addDecimals(1_000)));
        assertEq(s_childPool_2.getTargetBalance(), _takeRebalancerFee(_addDecimals(1_000)));

        uint256 usdcBalanceBefore = s_usdc.balanceOf(s_operator);

        vm.startPrank(s_operator);
        s_usdc.approve(address(s_childPool_1), type(uint256).max);
        s_usdc.approve(address(s_childPool_2), type(uint256).max);

        s_childPool_1.fillDeficit(s_childPool_1.getDeficit());
        s_childPool_2.fillDeficit(s_childPool_2.getDeficit());

        uint256 iouBalanceAfterFillDeficit = s_iouToken.balanceOf(s_operator);

        _takeSurplus(s_iouToken.balanceOf(s_operator));
        vm.stopPrank();

        uint256 usdcBalanceAfter = s_usdc.balanceOf(s_operator);
        uint256 rebalancerFee = s_parentPool.getRebalancerFee(iouBalanceAfterFillDeficit);

        assertEq(usdcBalanceAfter - usdcBalanceBefore, rebalancerFee);
    }

    function test_RebalancerFee_CalculatesCorrectlyWhenFullWithdrawal() public {
        test_RebalancerFee_CalculatesCorrectlyWhenDepositToEmptyPool();

        _enterWithdrawalQueue(s_user, s_lpToken.balanceOf(s_user));
        _fillChildPoolSnapshots();

        _triggerDepositWithdrawProcess();

        assertEq(s_childPool_1.getTargetBalance(), 0);
        assertEq(s_childPool_2.getTargetBalance(), 0);

        uint256 usdcBalanceBefore = s_usdc.balanceOf(s_operator);

        _fillDeficit(s_parentPool.getDeficit());
        uint256 iouBalanceAfterFillDeficit = s_iouToken.balanceOf(s_operator);
        uint256 rebalancerFee = s_parentPool.getRebalancerFee(iouBalanceAfterFillDeficit);

        _processPendingWithdrawals();

        /**
         * @dev We need to top up the rebalancer fee for the child pools
         * because a full withdrawal does not leave any liquidity in the child pools
         * to pay the rebalancer fee.
         */
        _topUpRebalancingFee(address(s_childPool_1), rebalancerFee / 2);
        _topUpRebalancingFee(address(s_childPool_2), rebalancerFee / 2);

        vm.startPrank(s_operator);
        s_iouToken.approve(address(s_childPool_1), type(uint256).max);
        s_iouToken.approve(address(s_childPool_2), type(uint256).max);

        s_childPool_1.takeSurplus(s_childPool_1.getSurplus());
        s_childPool_2.takeSurplus(s_childPool_2.getSurplus());
        vm.stopPrank();

        uint256 usdcBalanceAfter = s_usdc.balanceOf(s_operator);

        assertEq(usdcBalanceAfter - usdcBalanceBefore, rebalancerFee);
    }

    function test_RebalancerFee_ParentPoolRemaining() public {
        _setSupportedChildPools(9); // 9 child pools
        _setQueuesLength(0, 0);
        _enterDepositQueue(s_user, _addDecimals(1_000_000));
        _fillChildPoolSnapshots();
        _triggerDepositWithdrawProcess();

        assertEq(s_parentPool.getTargetBalance(), _takeRebalancerFee(_addDecimals(100_000)));
        assertEq(s_childPool_5.getTargetBalance(), _takeRebalancerFee(_addDecimals(100_000)));
        assertEq(s_childPool_9.getTargetBalance(), _takeRebalancerFee(_addDecimals(100_000)));

        vm.startPrank(s_operator);
        s_usdc.approve(address(s_childPool_1), type(uint256).max);
        s_usdc.approve(address(s_childPool_2), type(uint256).max);
        s_usdc.approve(address(s_childPool_3), type(uint256).max);
        s_usdc.approve(address(s_childPool_4), type(uint256).max);
        s_usdc.approve(address(s_childPool_5), type(uint256).max);
        s_usdc.approve(address(s_childPool_6), type(uint256).max);
        s_usdc.approve(address(s_childPool_7), type(uint256).max);
        s_usdc.approve(address(s_childPool_8), type(uint256).max);
        s_usdc.approve(address(s_childPool_9), type(uint256).max);

        s_childPool_1.fillDeficit(s_childPool_1.getDeficit());
        s_childPool_2.fillDeficit(s_childPool_2.getDeficit());
        s_childPool_3.fillDeficit(s_childPool_3.getDeficit());
        s_childPool_4.fillDeficit(s_childPool_4.getDeficit());
        s_childPool_5.fillDeficit(s_childPool_5.getDeficit());
        s_childPool_6.fillDeficit(s_childPool_6.getDeficit());
        s_childPool_7.fillDeficit(s_childPool_7.getDeficit());
        s_childPool_8.fillDeficit(s_childPool_8.getDeficit());
        s_childPool_9.fillDeficit(s_childPool_9.getDeficit());
        vm.stopPrank();

        _takeSurplus(s_iouToken.balanceOf(s_operator));
        _enterWithdrawalQueue(s_user, s_lpToken.balanceOf(s_user));
        _fillChildPoolSnapshots();
        _triggerDepositWithdrawProcess();

        _fillDeficit(s_parentPool.getDeficit());
        _processPendingWithdrawals();

        vm.startPrank(s_operator);
        s_iouToken.approve(address(s_childPool_1), type(uint256).max);
        s_iouToken.approve(address(s_childPool_2), type(uint256).max);
        s_iouToken.approve(address(s_childPool_3), type(uint256).max);
        s_iouToken.approve(address(s_childPool_4), type(uint256).max);
        s_iouToken.approve(address(s_childPool_5), type(uint256).max);
        s_iouToken.approve(address(s_childPool_6), type(uint256).max);
        s_iouToken.approve(address(s_childPool_7), type(uint256).max);
        s_iouToken.approve(address(s_childPool_8), type(uint256).max);
        s_iouToken.approve(address(s_childPool_9), type(uint256).max);

        s_childPool_1.takeSurplus(s_childPool_1.getSurplus());
        s_childPool_2.takeSurplus(s_childPool_2.getSurplus());
        s_childPool_3.takeSurplus(s_childPool_3.getSurplus());
        s_childPool_4.takeSurplus(s_childPool_4.getSurplus());
        s_childPool_5.takeSurplus(s_childPool_5.getSurplus());
        s_childPool_6.takeSurplus(s_childPool_6.getSurplus());
        s_childPool_7.takeSurplus(s_childPool_7.getSurplus());
        s_childPool_8.takeSurplus(s_childPool_8.getSurplus());
        s_childPool_9.takeSurplus(s_childPool_9.getSurplus());
        vm.stopPrank();

        assertEq(s_parentPool.getActiveBalance(), 0);
        assertEq(s_parentPool.exposed_getLancaFeeInLiqToken(), 0);
        assertApproxEqRel(
            s_parentPool.exposed_getRebalancingFeeInLiqToken(),
            _addDecimals(110),
            1e13
        );
    }

    function test_RebalancerFee_ExtraProfit() public {
        _setSupportedChildPools(2); // 2 child pools
        _setQueuesLength(0, 0);
        _enterDepositQueue(s_user, _addDecimals(1_200_000));
        _fillChildPoolSnapshots();
        _triggerDepositWithdrawProcess();

        vm.startPrank(s_deployer);
        s_childPool_1.setDstPool(childPoolChainSelector_2, address(s_childPool_2).toBytes32());
        s_childPool_2.setDstPool(childPoolChainSelector_1, address(s_childPool_1).toBytes32());
        vm.stopPrank();

        assertEq(s_parentPool.getTargetBalance(), _takeRebalancerFee(_addDecimals(400_000)));
        assertEq(s_childPool_1.getTargetBalance(), _takeRebalancerFee(_addDecimals(400_000)));
        assertEq(s_childPool_2.getTargetBalance(), _takeRebalancerFee(_addDecimals(400_000)));

        s_usdc.balanceOf(s_operator);

        vm.startPrank(s_operator);
        s_usdc.approve(address(s_childPool_1), type(uint256).max);
        s_usdc.approve(address(s_childPool_2), type(uint256).max);
        s_iouToken.approve(address(s_childPool_1), type(uint256).max);
        s_iouToken.approve(address(s_childPool_2), type(uint256).max);
        s_usdc.approve(address(s_parentPool), type(uint256).max);
        s_iouToken.approve(address(s_parentPool), type(uint256).max);

        s_childPool_1.fillDeficit(s_childPool_1.getDeficit());
        s_childPool_2.fillDeficit(s_childPool_2.getDeficit());

        s_parentPool.takeSurplus(s_iouToken.balanceOf(s_operator));
        vm.stopPrank();

        _enterDepositQueue(s_user, _addDecimals(100));

        uint256 totalFlow = _addDecimals(3_000_000);
        s_parentPool.exposed_setChildPoolSnapshot(
            childPoolChainSelector_1,
            _getChildPoolSnapshot(_addDecimals(400_000), totalFlow, totalFlow)
        );
        s_parentPool.exposed_setChildPoolSnapshot(
            childPoolChainSelector_2,
            _getChildPoolSnapshot(_addDecimals(400_000), totalFlow, totalFlow)
        );
        _triggerDepositWithdrawProcess();

        assertApproxEqRel(s_parentPool.getSurplus(), _addDecimals(103_780), 1e15);
        assertApproxEqRel(s_childPool_1.getDeficit(), _addDecimals(51_930), 1e15);
        assertApproxEqRel(s_childPool_2.getDeficit(), _addDecimals(51_930), 1e15);

        vm.startPrank(s_operator);
        s_childPool_1.fillDeficit(s_childPool_1.getDeficit());
        s_childPool_2.fillDeficit(s_childPool_2.getDeficit());
        vm.stopPrank();

        uint256 lastDepositRebalancerFee = s_parentPool.getRebalancerFee(_addDecimals(100));
        uint256 rebalancerExtraProfit = s_parentPool.getRebalancerFee(
            s_iouToken.balanceOf(s_operator)
        ) - lastDepositRebalancerFee;

        assertApproxEqRel(rebalancerExtraProfit, _addDecimals(10), 4e16);
    }

    // /* -- Post inflow rebalance -- */

    /*
     * @dev totalWithdrawalAmountLocked should be 0 when active balance
     * less than targetBalanceFloor
     */
    function test_postInflowRebalance_totalWithdrawalAmountLockedShouldBeZero() public {
        _baseSetupWithLPMinting();

        address user1 = _getUsers(1)[0];
        uint256 usdcBalanceBefore = s_usdc.balanceOf(user1);
        _enterWithdrawalQueue(user1, _takeRebalancerFee(_addDecimals(2_000)));

        // Imagine that someone send 1000 USDC from ParentPool to ChildPool
        _fillChildPoolSnapshots(_addDecimals(1_000));
        MockERC20(address(s_usdc)).burn(address(s_parentPool), _addDecimals(1_000));
        s_parentPool.exposed_setChildPoolSnapshot(
            1,
            _getChildPoolSnapshot(_addDecimals(2_000), 0, 0)
        );
        assertEq(s_usdc.balanceOf(address(s_parentPool)), 0);

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
        assertEq(s_parentPool.getActiveBalance(), _addDecimals(800));

        // User1 should have 2000 USDC
        assertEq(
            s_usdc.balanceOf(user1),
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

    function test_takeSurplus_CalculatesNewIOUAmount_WhenFullWithdrawal() public {
        vm.prank(s_deployer);
        s_parentPool.setLiquidityCap(_addDecimals(5_000));

        _setQueuesLength(0, 0);
        _enterDepositQueue(s_user, _addDecimals(5_000));

        _fillChildPoolSnapshots();
        _triggerDepositWithdrawProcess();

        assertEq(s_childPool_1.getTargetBalance(), _addDecimals(0));
    }

    function test_takeSurplus_RevertsIfAmountExceedsSurplus() public {
        vm.expectRevert(abi.encodeWithSelector(IRebalancer.AmountExceedsSurplus.selector, 0, 1));
        s_parentPool.takeSurplus(1);
    }

    function test_bridgeIOU_RevertsIfAmountIsZero() public {
        vm.expectRevert(ICommonErrors.AmountIsZero.selector);
        s_parentPool.bridgeIOU(s_user.toBytes32(), 1, 0);
    }

    function test_bridgeIOU_RevertsIfInvalidDestinationChain() public {
        vm.expectRevert(abi.encodeWithSelector(ICommonErrors.InvalidDstChainSelector.selector, 5));
        s_parentPool.bridgeIOU(s_user.toBytes32(), 5, 1);
    }

    function test_getIouToken() public view {
        assertEq(s_parentPool.getIOUToken(), address(s_iouToken));
    }
}
