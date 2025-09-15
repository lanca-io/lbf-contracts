// SPDX-License-Identifier: UNLICENSED
/* solhint-disable func-name-mixedcase */
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

    /** -- Test Target Balances calculation -- */

    function test_initialDepositAndUpdateTargetBalances(uint256 amountToDepositPerUser) public {
        vm.assume(amountToDepositPerUser > 0 && amountToDepositPerUser < MAX_DEPOSIT_AMOUNT);

        _mintUsdc(user, amountToDepositPerUser * s_parentPool.getMinDepositQueueLength());

        vm.prank(deployer);
        s_parentPool.setMinWithdrawalQueueLength(0);

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
            (103765207505 * LIQ_TOKEN_SCALE_FACTOR) / 1000000,
            (109837384883 * LIQ_TOKEN_SCALE_FACTOR) / 1000000,
            (89237488257 * LIQ_TOKEN_SCALE_FACTOR) / 1000000,
            (99148043512 * LIQ_TOKEN_SCALE_FACTOR) / 1000000
        ];
        uint256 expectedParentPoolTargetBalance = (97811875840 * LIQ_TOKEN_SCALE_FACTOR) / 1000000;

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

        assertEq(userLiqTokenBalanceAfter - userLiqTokenBalanceBefore, 10198980000);
        assertEq(s_parentPool.isReadyToProcessPendingWithdrawals(), false);
        assertEq(s_parentPool.getPendingWithdrawalIds().length, 0);
    }

    /** -- Test LP Token amount calculation -- */

    function test_calculateLpTokenAmountInEmptyPool() public {
        vm.startPrank(deployer);
        s_parentPool.setMinDepositQueueLength(1);
        s_parentPool.setMinWithdrawalQueueLength(0);
        vm.stopPrank();

        _fillChildPoolSnapshots();

        uint256 lpBalanceBefore = lpToken.balanceOf(user);
        uint256 amountToDeposit = 100 * LIQ_TOKEN_SCALE_FACTOR;

        vm.prank(user);
        s_parentPool.enterDepositQueue(amountToDeposit);

        vm.prank(s_lancaKeeper);
        s_parentPool.triggerDepositWithdrawProcess();

        uint256 lpTokenBalanceAfter = lpToken.balanceOf(user);

        assertEq(
            lpTokenBalanceAfter - lpBalanceBefore,
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

    function test_calculateLpWhenDepositWithdrawalQueue() public {
        // deposit amount 100.000000 USDC
        // get LP after deposit -> amountToDeposit - rebalancerFee = 99.990000 LP

        uint256 lpBalanceBefore = lpToken.balanceOf(user);
        uint256 amountToDeposit = 100 * LIQ_TOKEN_SCALE_FACTOR; // 100 USDC

        vm.prank(user);
        s_parentPool.enterDepositQueue(amountToDeposit);

        _setQueuesLength(0, 0);
        _fillChildPoolSnapshots();
        _triggerDepositWithdrawProcess();

        uint256 lpBalanceAfterDeposit = lpToken.balanceOf(user);
        uint256 amountToDepositWithFee = amountToDeposit -
            s_parentPool.getRebalancerFee(amountToDeposit);

        assertEq(lpBalanceAfterDeposit, lpBalanceBefore + amountToDepositWithFee);

        // deposit again 100.000000 USDC -> 99.990000 LP
        // withdraw half - 99.990000

        vm.startPrank(user);
        s_parentPool.enterDepositQueue(amountToDeposit);

        lpToken.approve(address(s_parentPool), type(uint256).max);
        s_parentPool.enterWithdrawalQueue(lpBalanceAfterDeposit);
        vm.stopPrank();

        _fillChildPoolSnapshots();
        _triggerDepositWithdrawProcess();
        _processPendingWithdrawals();

        // final LP balance should be 99.990000

        uint256 lpTokenBalanceAfterDepositWithdraw = lpToken.balanceOf(user);
        assertEq(lpTokenBalanceAfterDepositWithdraw, lpBalanceAfterDeposit);
    }

    /** -- Test Liquidity Token amount calculation -- */

    function test_calculateLIQWhenDepositWithdrawalQueueWithInflow() public {
        // Setting pools
        vm.prank(deployer);
        s_parentPool.setLiquidityCap(_addDecimals(10_000));

        _setSupportedChildPools(10);
        _setQueuesLength(0, 0);
        _mintUsdc(address(s_parentPool), _addDecimals(1_000));
        _setupParentPoolWithBaseExample();

        // Mock LP token balance
        address user1 = makeAddr("user1");
        _mintLpToken(address(this), _takeRebalancerFee(_addDecimals(10_000)));
        lpToken.transfer(user1, _takeRebalancerFee(_addDecimals(2_000)));
        uint256 usdcBalanceBefore = usdc.balanceOf(user1);

        // -- Enter withdrawal queue 1 --
        _enterWithdrawalQueue(user1, _takeRebalancerFee(_addDecimals(500)));

        _fillChildPoolSnapshots(10);
        _triggerDepositWithdrawProcess();

        // -- Fill deficit --
        // after withdrawal 500 USDC, new targetBalance 950 (floor)
        // but temporary targetBalance for ParentPool is 1_450 (950 + 500)
        // current USDC balance is 1_000
        // deficit is 450 USDC (1_450 - 1_000 or targetBalance - activeBalance)
        uint256 deficit = s_parentPool.getDeficit();
        assertEq(deficit, _addDecimals(450));
        vm.prank(operator);
        s_parentPool.fillDeficit(deficit);

        // -- Enter withdrawal queue 2 --
        _enterWithdrawalQueue(user1, _takeRebalancerFee(_addDecimals(1_500)));

        _fillChildPoolSnapshots(10);
        _triggerDepositWithdrawProcess();

        // // -- Deposit for 2 users --
        address user2 = makeAddr("user2");
        address user3 = makeAddr("user3");
        uint256 amountToDeposit = _addDecimals(1_000);
        uint256 amountToDepositExtra = _addDecimals(500);
        _mintUsdc(user2, amountToDeposit);
        _mintUsdc(user3, amountToDeposit + amountToDepositExtra);

        _enterDepositQueue(user2, amountToDeposit);
        _enterDepositQueue(user3, amountToDeposit + amountToDepositExtra);

        _fillChildPoolSnapshots(10);
        _triggerDepositWithdrawProcess();

        // Now we have an initial target balance for all pools of about 1_050 USDC
        // and a surplus of about 900 USDC
        //      - 450 was added by the Operator
        //      - 500 is an extra deposit
        //      - 50 should stay in the ParentPool
        //      - 450 should be covered by the deficit in the child pools
        //      - 450 + 500 – 50 = 900
        // This means that the system received a deposit of 500 USDC (10_000 – 2_000 + 2_500)
        // The final inflow equals 500 USDC
        // Now 450 IOU can be exchanged for USDC in the ParentPool
        // and 450 IOU can be obtained in the child pools and exchanged for USDC in the ParentPool
        assertTrue(
            s_parentPool.getTargetBalance() > _addDecimals(1_049) &&
                s_parentPool.getTargetBalance() < _addDecimals(1_050)
        );
        assertTrue(
            s_parentPool.getSurplus() > _addDecimals(899) &&
                s_parentPool.getSurplus() < _addDecimals(900)
        );

        vm.startPrank(operator);
        iouToken.approve(address(s_parentPool), _addDecimals(450));
        s_parentPool.takeSurplus(_addDecimals(450));
        vm.stopPrank();

        // Final withdrawals
        // user1 can withdraw 2_000 USDC - fee
        _processPendingWithdrawals();
        assertEq(
            usdc.balanceOf(user1),
            usdcBalanceBefore + _takeWithdrawalFee(_addDecimals(2_000))
        );
        assertGt(usdc.balanceOf(address(s_parentPool)), _addDecimals(1500));
    }

    function test_calculateLIQWhenDepositWithdrawalQueueWithOutflow() public {
        // Setting pools
        vm.prank(deployer);
        s_parentPool.setLiquidityCap(_addDecimals(10_000));

        _setSupportedChildPools(10);
        _setQueuesLength(0, 0);
        _mintUsdc(address(s_parentPool), _addDecimals(1_000));
        _setupParentPoolWithBaseExample();

        // Mock LP token balance
        address user1 = makeAddr("user1");
        _mintLpToken(address(this), _takeRebalancerFee(_addDecimals(10_000)));
        lpToken.transfer(user1, _takeRebalancerFee(_addDecimals(2_000)));
        uint256 usdcBalanceBefore = usdc.balanceOf(user1);

        // -- Enter withdrawal queue 1 --
        _enterWithdrawalQueue(user1, _takeRebalancerFee(_addDecimals(1_000)));

        _fillChildPoolSnapshots(10);
        _triggerDepositWithdrawProcess();

        // -- Fill deficit --
        // after withdrawal 1_000 USDC, new targetBalance 900 (floor)
        // but temporary targetBalance for ParentPool is 1_900 (900 + 1_000)
        // current USDC balance is 1_000
        // deficit is 900 USDC (1_900 - 1_000 or targetBalance - activeBalance)
        uint256 deficit = s_parentPool.getDeficit();
        assertEq(deficit, _addDecimals(900));
        vm.prank(operator);
        s_parentPool.fillDeficit(_addDecimals(500)); // bit more than half of the deficit

        // -- Enter withdrawal queue 2 --
        _enterWithdrawalQueue(user1, _takeRebalancerFee(_addDecimals(1_000)));

        _fillChildPoolSnapshots(10);
        _triggerDepositWithdrawProcess();

        // // -- Deposit for 2 users --
        address user2 = makeAddr("user2");
        address user3 = makeAddr("user3");
        _mintUsdc(user2, _addDecimals(1_000));
        _mintUsdc(user3, _addDecimals(1_000));

        uint256 coverFee = _addDecimals(1); // add 1 USDC to cover the fee and trigger processInflow
        _enterDepositQueue(user2, _addDecimals(1_000));
        _enterDepositQueue(user3, _addDecimals(500) + coverFee);

        _fillChildPoolSnapshots(10);
        _triggerDepositWithdrawProcess();

        // Now we have targetBalance for all pools about 950 USDC
        // and surplus about 50 USDC, because 500 USDC was added by Operator
        // it means that system lost 500 USDC on withdrawals (10_000 - 2_000 + 1_500)
        // Final outflow equals 500 USDC
        // Now 500 IOU can be exchanged for USDC by requesting 50 in each pool
        assertTrue(
            s_parentPool.getTargetBalance() > _addDecimals(950) &&
                s_parentPool.getTargetBalance() < _addDecimals(951)
        );
        assertTrue(
            s_parentPool.getSurplus() > _addDecimals(50) &&
                s_parentPool.getSurplus() < _addDecimals(51)
        );

        vm.startPrank(operator);
        iouToken.approve(address(s_parentPool), _addDecimals(50));
        s_parentPool.takeSurplus(_addDecimals(50));
        vm.stopPrank();

        // Final withdrawals
        // user1 can withdraw 2_000 USDC - fee
        _processPendingWithdrawals();
        assertEq(
            usdc.balanceOf(user1),
            usdcBalanceBefore + _takeWithdrawalFee(_addDecimals(2_000))
        );

        assertGt(usdc.balanceOf(address(s_parentPool)), _addDecimals(950));
    }

    function test_calculateLIQWhenDepositWithdrawalQueue() public {
        // example without fees
        // (x3) users deposit 100 USDC -> 100 LP
        // (x2) users withdraw 100 LP -> 100 USDC
        // user1 USDC balance should be equal to user2 USDC balance after withdrawal

        // ----------- deposit for 3 users -------------
        uint256 amountToDeposit = 100 * LIQ_TOKEN_SCALE_FACTOR;
        address[3] memory users = [makeAddr("user1"), makeAddr("user2"), makeAddr("user3")];

        for (uint256 i; i < users.length; i++) {
            _mintUsdc(users[i], amountToDeposit);
            vm.prank(users[i]);
            usdc.approve(address(s_parentPool), type(uint256).max);
        }

        for (uint256 i; i < users.length; i++) {
            vm.prank(users[i]);
            s_parentPool.enterDepositQueue(amountToDeposit);
        }

        _setQueuesLength(0, 0);
        _fillChildPoolSnapshots();
        _triggerDepositWithdrawProcess();

        uint256 lpAmountWithFee = amountToDeposit - s_parentPool.getRebalancerFee(amountToDeposit);

        for (uint256 i; i < users.length; i++) {
            assertEq(lpToken.balanceOf(users[i]), lpAmountWithFee);
            assertEq(usdc.balanceOf(users[i]), 0);
        }

        // ------------ withdraw for 2 users -------------
        for (uint256 i; i < 2; i++) {
            vm.startPrank(users[i]);
            lpToken.approve(address(s_parentPool), type(uint256).max);
            s_parentPool.enterWithdrawalQueue(lpAmountWithFee);
            vm.stopPrank();
        }

        _fillChildPoolSnapshots();
        _triggerDepositWithdrawProcess();
        _processPendingWithdrawals();

        uint256[3] memory balanceAfterWithdrawal = [uint256(0), uint256(0), uint256(0)];
        for (uint256 i; i < users.length; i++) {
            balanceAfterWithdrawal[i] = usdc.balanceOf(users[i]);
        }

        assertTrue(
            balanceAfterWithdrawal[0] > 0 &&
                balanceAfterWithdrawal[1] > 0 &&
                balanceAfterWithdrawal[2] == 0
        );

        assertEq(balanceAfterWithdrawal[0], balanceAfterWithdrawal[1]);
    }
}
