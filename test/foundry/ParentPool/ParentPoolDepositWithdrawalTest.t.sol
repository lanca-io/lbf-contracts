// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {ParentPoolBase} from "./ParentPoolBase.sol";
import {IBase} from "../../../contracts/Base/interfaces/IBase.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IParentPool} from "../../../contracts/ParentPool/interfaces/IParentPool.sol";

import "forge-std/src/console.sol";

contract ParentPoolDepositWithdrawalTest is ParentPoolBase {
    function setUp() public override {
        super.setUp();
        vm.warp(NOW_TIMESTAMP);
    }

    function test_initialDepositAndUpdateTargetBalances(uint256 amountToDepositPerUser) public {
        vm.assume(amountToDepositPerUser > 0 && amountToDepositPerUser < MAX_DEPOSIT_AMOUNT);

        _mintUsdc(user, amountToDepositPerUser * s_parentPool.getMinDepositQueueLength());

        vm.prank(deployer);
        s_parentPool.setMinWithdrawalQueueLength(0);

        uint256 initialParentPoolBalance = s_parentPool.getActiveBalance();

        _fillDepositWithdrawalQueue(amountToDepositPerUser, 0);
        _fillChildPoolSnapshots();

        vm.prank(s_lancaKeeper);
        s_parentPool.triggerDepositWithdrawProcess();

        // @dev A fee is charged on part of the amount, not on the entire amount, in order to maintain accuracy
        uint256 totalDeposited;
        for (uint256 i; i < s_parentPool.getMinDepositQueueLength(); ++i) {
            totalDeposited +=
                amountToDepositPerUser - s_parentPool.getRebalancerFee(amountToDepositPerUser);
        }

        uint24[] memory childPoolChainSelectors = _getChildPoolsChainSelectors();

        uint256 expectedPoolTargetBalance = totalDeposited / (childPoolChainSelectors.length + 1);

        vm.assertEq(s_parentPool.getActiveBalance(), totalDeposited);
        vm.assertEq(expectedPoolTargetBalance, s_parentPool.getTargetBalance());

        for (uint256 i; i < childPoolChainSelectors.length; ++i) {
            vm.assertEq(
                expectedPoolTargetBalance,
                s_parentPool.exposed_getChildPoolTargetBalance(childPoolChainSelectors[i])
            );
        }
    }

    function test_recalculateTargetBalancesWithInflow() public {
        vm.prank(deployer);
        s_parentPool.setMinWithdrawalQueueLength(0);

        _mintUsdc(address(s_parentPool), 110_000 * LIQ_TOKEN_SCALE_FACTOR);

        _setupParentPoolWithWhitePaperExample();

        uint256 remainingAmount = 10_000 * LIQ_TOKEN_SCALE_FACTOR;
        uint256 amountToDepositPerUser = remainingAmount / s_parentPool.getMinDepositQueueLength();
        _fillDepositWithdrawalQueue(
            amountToDepositPerUser + s_parentPool.getRebalancerFee(amountToDepositPerUser),
            0
        );

        vm.prank(s_lancaKeeper);
        s_parentPool.triggerDepositWithdrawProcess();

        uint256[4] memory childPoolsExpectedTargetBalances = [
            (103806730177 * LIQ_TOKEN_SCALE_FACTOR) / 1000000,
            (109881337396 * LIQ_TOKEN_SCALE_FACTOR) / 1000000,
            (89273197519 * LIQ_TOKEN_SCALE_FACTOR) / 1000000,
            (99187718579 * LIQ_TOKEN_SCALE_FACTOR) / 1000000
        ];

        for (uint256 i; i < _getChildPoolsChainSelectors().length; ++i) {
            assertEq(
                s_parentPool.exposed_getChildPoolTargetBalance(_getChildPoolsChainSelectors()[i]),
                childPoolsExpectedTargetBalances[i]
            );
        }

        uint256 expectedParentPoolTargetBalance = (97851016227 * LIQ_TOKEN_SCALE_FACTOR) / 1000000;
        assertEq(s_parentPool.getTargetBalance(), expectedParentPoolTargetBalance);
    }

    function test_recalculateTargetBalancesWithOutflow() public {
        vm.prank(deployer);
        s_parentPool.setMinDepositQueueLength(0);

        uint256 userLiqTokenBalanceBefore = usdc.balanceOf(user);

        assertEq(s_parentPool.isReadyToProcessPendingWithdrawals(), false);

        uint256 lpUserBalance = 500_000 * LIQ_TOKEN_SCALE_FACTOR;
        _mintLpToken(user, lpUserBalance);

        vm.prank(user);
        lpToken.approve(address(s_parentPool), type(uint256).max);

        _mintUsdc(address(s_parentPool), 130_000 * LIQ_TOKEN_SCALE_FACTOR);
        _setupParentPoolWithWhitePaperExample();

        uint256 remainingAmount = 10_000 * LIQ_TOKEN_SCALE_FACTOR;
        uint256 amountToWithdrawPerUser = remainingAmount /
            s_parentPool.getMinWithdrawalQueueLength();
        _fillDepositWithdrawalQueue(0, amountToWithdrawPerUser);

        vm.prank(s_lancaKeeper);
        s_parentPool.triggerDepositWithdrawProcess();

        uint256[4] memory childPoolsExpectedTargetBalances = [
            (103782081134 * LIQ_TOKEN_SCALE_FACTOR) / 1000000,
            (109855245930 * LIQ_TOKEN_SCALE_FACTOR) / 1000000,
            (89251999482 * LIQ_TOKEN_SCALE_FACTOR) / 1000000,
            (99164166327 * LIQ_TOKEN_SCALE_FACTOR) / 1000000
        ];
        uint256 expectedParentPoolTargetBalance = (97827781377 * LIQ_TOKEN_SCALE_FACTOR) / 1000000;

        for (uint256 i; i < _getChildPoolsChainSelectors().length; ++i) {
            assertEq(
                s_parentPool.exposed_getChildPoolTargetBalance(_getChildPoolsChainSelectors()[i]),
                childPoolsExpectedTargetBalances[i]
            );
        }

        assertEq(s_parentPool.getTargetBalance(), expectedParentPoolTargetBalance);
        assertEq(s_parentPool.isReadyToProcessPendingWithdrawals(), true);

        vm.prank(s_lancaKeeper);
        s_parentPool.processPendingWithdrawals();

        uint256 userLiqTokenBalanceAfter = usdc.balanceOf(user);

        assertEq(userLiqTokenBalanceAfter - userLiqTokenBalanceBefore, 10117713876);
        assertEq(s_parentPool.isReadyToProcessPendingWithdrawals(), false);
        assertEq(s_parentPool.getPendingWithdrawalIds().length, 0);
    }

    function test_calculateLpTokenAmountInEmptyPool() public {
        vm.startPrank(deployer);
        s_parentPool.setMinDepositQueueLength(1);
        s_parentPool.setMinWithdrawalQueueLength(0);
        vm.stopPrank();

        _fillChildPoolSnapshots();

        uint256 lpTokenBalanceBefore = lpToken.balanceOf(user);
        uint256 amountToDeposit = 100 * LIQ_TOKEN_SCALE_FACTOR;

        vm.prank(user);
        s_parentPool.enterDepositQueue(amountToDeposit);

        vm.prank(s_lancaKeeper);
        s_parentPool.triggerDepositWithdrawProcess();

        uint256 lpTokenBalanceAfter = lpToken.balanceOf(user);

        assertEq(
            lpTokenBalanceAfter - lpTokenBalanceBefore,
            amountToDeposit - s_parentPool.getRebalancerFee(amountToDeposit)
        );
    }

    function test_calculateLpTokenAmountDepositQueueInEmptyPool() public {
        vm.startPrank(deployer);
        s_parentPool.setMinDepositQueueLength(3);
        s_parentPool.setMinWithdrawalQueueLength(0);
        vm.stopPrank();

        _fillChildPoolSnapshots();

        uint256 amountToWithdraw = 100 * LIQ_TOKEN_SCALE_FACTOR;

        address[3] memory users = [makeAddr("user1"), makeAddr("user2"), makeAddr("user3")];
        uint256[3] memory balancesBefore = [uint256(0), uint256(0), uint256(0)];

        for (uint256 i; i < users.length; ++i) {
            _mintUsdc(users[i], amountToWithdraw);
            balancesBefore[i] = usdc.balanceOf(users[i]);
            _enterDepositQueue(users[i], amountToWithdraw);
        }

        vm.prank(s_lancaKeeper);
        s_parentPool.triggerDepositWithdrawProcess();

        uint256[3] memory balancesAfter = [uint256(0), uint256(0), uint256(0)];

        for (uint256 i; i < users.length; ++i) {
            assertEq(balancesBefore[i] - usdc.balanceOf(users[i]), amountToWithdraw);
            assertEq(
                lpToken.balanceOf(users[i]),
                amountToWithdraw - s_parentPool.getRebalancerFee(amountToWithdraw)
            );
        }
        assertEq(
            lpToken.totalSupply(),
            (amountToWithdraw - s_parentPool.getRebalancerFee(amountToWithdraw)) * users.length
        );
    }

    function test_calculateLpTokenAmountWhenDepositAndWithdrawalQueue() public {
        test_calculateLpTokenAmountDepositQueueInEmptyPool();

        uint256 amountToDeposit = 100 * LIQ_TOKEN_SCALE_FACTOR;
        uint256 amountToWithdraw = amountToDeposit - s_parentPool.getRebalancerFee(amountToDeposit);

        address user1 = makeAddr("user1");
        _mintUsdc(user1, amountToDeposit);
        _setQueuesLength(1, 1);

        uint256 lpTokenBalanceBefore = lpToken.balanceOf(user1);
        uint256 usdcBalanceBefore = usdc.balanceOf(user1);
        console.log("lpTokenBalanceBefore", lpTokenBalanceBefore);
        console.log("usdcBalanceBefore", usdcBalanceBefore);

        vm.startPrank(user1);
        usdc.approve(address(s_parentPool), type(uint256).max);
        s_parentPool.enterDepositQueue(amountToDeposit);

        lpToken.approve(address(s_parentPool), type(uint256).max);
        s_parentPool.enterWithdrawalQueue(amountToWithdraw);
        vm.stopPrank();

        _setupParentPoolWithWhitePaperExample();
        _triggerDepositWithdrawProcess();

        vm.prank(s_lancaKeeper);
        // s_parentPool.processPendingWithdrawals();

        // uint256 lpTokenBalanceAfter = lpToken.balanceOf(user1);
        // uint256 usdcBalanceAfter = usdc.balanceOf(user1);

        // console.log("lpTokenBalanceAfter", lpTokenBalanceAfter);
        // console.log("usdcBalanceAfter", usdcBalanceAfter);

        // TODO: Finish this test

        // assertEq(lpTokenBalanceAfter - lpTokenBalanceBefore, amountToDeposit - s_parentPool.getRebalancerFee(amountToDeposit));
        // assertEq(usdcBalanceAfter - usdcBalanceBefore, amountToWithdraw);
    }
}
