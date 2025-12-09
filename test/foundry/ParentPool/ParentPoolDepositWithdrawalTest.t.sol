// SPDX-License-Identifier: UNLICENSED
/* solhint-disable func-name-mixedcase */
pragma solidity 0.8.28;

import {ParentPoolBase} from "./ParentPoolBase.sol";
import {ICommonErrors} from "contracts/common/interfaces/ICommonErrors.sol";
import {IParentPool} from "contracts/ParentPool/interfaces/IParentPool.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {Vm} from "forge-std/src/Vm.sol";

import {console} from "forge-std/src/console.sol";

contract ParentPoolDepositWithdrawalTest is ParentPoolBase {
    function setUp() public override {
        super.setUp();
        vm.warp(NOW_TIMESTAMP);
    }

    function test_inflationAttackNotPossible() public {
        // We have this check on enterDepositQueue:
        // 		require(minDepositAmount > 0, ICommonErrors.MinDepositAmountNotSet());
        // it means that minDepositAmount will be set after initialization
        // and hacker can't frontrun this transaction
        // because deposit is possible only after triggerDepositWithdrawProcess
        //
        // it also means that cost of this attack will be too high,
        // but flash loan attack is not possible (2 tx: enterDepositQueue and triggerDepositWithdrawProcess)

        // Example of attack:
        _setQueuesLength(0, 0);

        vm.expectRevert(
            abi.encodeWithSelector(
                ICommonErrors.DepositAmountIsTooLow.selector,
                1,
                _addDecimals(100)
            )
        );
        vm.prank(s_user);
        s_parentPool.enterDepositQueue(1);
    }

    /** -- Test Target Balances calculation -- */

    function testFuzz_initialDepositAndUpdateTargetBalances(uint256 amountToDepositPerUser) public {
        _setLiquidityCap(address(s_parentPool), type(uint256).max);
        vm.assume(
            amountToDepositPerUser > s_parentPool.getMinDepositAmount() &&
                amountToDepositPerUser < MAX_DEPOSIT_AMOUNT
        );

        _mintUsdc(s_user, amountToDepositPerUser * s_parentPool.getMinDepositQueueLength());

        vm.prank(s_deployer);
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

        vm.assertApproxEqRel(s_parentPool.getActiveBalance(), totalDeposited, 1e11);
        vm.assertEq(expectedPoolTargetBalance, s_parentPool.getTargetBalance());

        for (uint256 i; i < childPoolChainSelectors.length; ++i) {
            vm.assertEq(
                expectedPoolTargetBalance,
                s_parentPool.exposed_getChildPoolTargetBalance(childPoolChainSelectors[i])
            );
        }
    }

    function test_recalculateTargetBalancesWithInflow() public {
        vm.prank(s_deployer);
        s_parentPool.setMinWithdrawalQueueLength(0);

        _mintUsdc(address(s_parentPool), _addDecimals(110_000));
        _setLiquidityCap(address(s_parentPool), _addDecimals(11_000));

        _setupParentPoolWithWhitePaperExample();

        uint256 remainingAmount = _addDecimals(10_000);
        uint256 amountToDepositPerUser = remainingAmount / s_parentPool.getMinDepositQueueLength();
        _fillDepositWithdrawalQueue(
            amountToDepositPerUser + s_parentPool.getRebalancerFee(amountToDepositPerUser),
            0
        );

        vm.prank(s_lancaKeeper);
        s_parentPool.triggerDepositWithdrawProcess();

        uint256[4] memory childPoolsExpectedTargetBalances = [
            (_addDecimals(103806730177) / 1000000),
            (_addDecimals(109881337396) / 1000000),
            (_addDecimals(89273197519) / 1000000),
            (_addDecimals(99187718579) / 1000000)
        ];

        for (uint256 i; i < _getChildPoolsChainSelectors().length; ++i) {
            assertEq(
                s_parentPool.exposed_getChildPoolTargetBalance(_getChildPoolsChainSelectors()[i]),
                childPoolsExpectedTargetBalances[i]
            );
        }

        uint256 expectedParentPoolTargetBalance = _addDecimals(97851016227) / 1000000;
        assertEq(s_parentPool.getTargetBalance(), expectedParentPoolTargetBalance);
    }

    function test_recalculateTargetBalancesWithOutflow() public {
        vm.prank(s_deployer);
        s_parentPool.setMinDepositQueueLength(0);

        uint256 userLiqTokenBalanceBefore = s_usdc.balanceOf(s_user);

        assertEq(s_parentPool.isReadyToProcessPendingWithdrawals(), false);

        uint256 lpUserBalance = 500_000 * USDC_TOKEN_DECIMALS_SCALE;
        _mintLpToken(s_user, lpUserBalance);

        vm.prank(s_user);
        s_lpToken.approve(address(s_parentPool), type(uint256).max);

        _mintUsdc(address(s_parentPool), 130_000 * USDC_TOKEN_DECIMALS_SCALE);
        _setupParentPoolWithWhitePaperExample();

        uint256 remainingAmount = 10_000 * USDC_TOKEN_DECIMALS_SCALE;
        uint256 amountToWithdrawPerUser = remainingAmount /
            s_parentPool.getMinWithdrawalQueueLength();
        _fillDepositWithdrawalQueue(0, amountToWithdrawPerUser);

        vm.prank(s_lancaKeeper);
        s_parentPool.triggerDepositWithdrawProcess();

        uint256[4] memory childPoolsExpectedTargetBalances = [
            (103765207505 * USDC_TOKEN_DECIMALS_SCALE) / 1000000,
            (109837384883 * USDC_TOKEN_DECIMALS_SCALE) / 1000000,
            (89237488257 * USDC_TOKEN_DECIMALS_SCALE) / 1000000,
            (99148043512 * USDC_TOKEN_DECIMALS_SCALE) / 1000000
        ];
        uint256 expectedParentPoolTargetBalance = (97811875840 * USDC_TOKEN_DECIMALS_SCALE) /
            1000000;

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

        uint256 userLiqTokenBalanceAfter = s_usdc.balanceOf(s_user);

        assertEq(userLiqTokenBalanceAfter - userLiqTokenBalanceBefore, 10198980000);
        assertEq(s_parentPool.isReadyToProcessPendingWithdrawals(), false);
        assertEq(s_parentPool.getPendingWithdrawalIds().length, 0);
    }

    function test_recalculateTargetBalancesWhenChildPoolCantReceiveSnapshot() public {
        _baseSetupWithLPMinting();

        address user1 = _getUsers(1)[0];
        _enterWithdrawalQueue(user1, _takeRebalancerFee(_addDecimals(2_000)));
        _fillChildPoolSnapshots(_addDecimals(1_000));
        _triggerDepositWithdrawProcess();

        for (uint24 i = 1; i <= 9; i++) {
            uint256 childPoolTargetBalance = s_parentPool.exposed_getChildPoolTargetBalance(i);
            assertEq(childPoolTargetBalance, _addDecimals(800));
        }
        assertEq(s_parentPool.getTargetBalance(), _addDecimals(2600));

        // Even if child pool can't receive previous snapshot,
        // new target balance should be recalculated correctly
        _enterDepositQueue(s_user, _addDecimals(1_000));
        _fillChildPoolSnapshots(_addDecimals(1_000));
        _fillDeficit(_addDecimals(1_800));
        _triggerDepositWithdrawProcess();

        for (uint24 i = 1; i <= 9; i++) {
            uint256 childPoolTargetBalance = s_parentPool.exposed_getChildPoolTargetBalance(i);
            assertApproxEqRel(childPoolTargetBalance, _addDecimals(900), 1e14);
        }
        assertEq(s_parentPool.getDeficit(), 0);
        assertApproxEqRel(s_parentPool.getTargetBalance(), _addDecimals(900), 1e14);
    }

    function test_recalculateTargetBalanceWhenAddingNewEmptyPool() public {
        _setSupportedChildPools(8);
        _setQueuesLength(0, 0);
        _mintUsdc(address(s_parentPool), _addDecimals(1_000));
        _mintLpToken(s_user, _takeRebalancerFee(_addDecimals(9_000)));
        _setupParentPoolWithBaseExample();

        uint256 childPoolsLength = s_parentPool.getChildPoolChainSelectors().length;
        assertEq(childPoolsLength, 8);

        for (uint24 i = 1; i <= childPoolsLength; i++) {
            uint256 childPoolTargetBalance = s_parentPool.exposed_getChildPoolTargetBalance(i);
            assertEq(childPoolTargetBalance, _addDecimals(1_000));
        }
        assertEq(s_parentPool.getTargetBalance(), _addDecimals(1_000));

        _setSupportedChildPools(9); // Add new empty pool
        childPoolsLength = s_parentPool.getChildPoolChainSelectors().length;
        assertEq(childPoolsLength, 9);
        assertEq(s_parentPool.exposed_getChildPoolTargetBalance(9), 0);

        _enterDepositQueue(s_user, _addDecimals(1_000));

        uint24[] memory childPoolChainSelectors = s_parentPool.getChildPoolChainSelectors();
        for (uint256 i; i < childPoolChainSelectors.length - 1; ++i) {
            s_parentPool.exposed_setChildPoolSnapshot(
                childPoolChainSelectors[i],
                _getChildPoolSnapshot(_addDecimals(1_000), _addDecimals(500), _addDecimals(500))
            );
        }
        s_parentPool.exposed_setYesterdayFlow(_addDecimals(5_000), _addDecimals(5_000));
        s_parentPool.exposed_setChildPoolSnapshot(9, _getChildPoolSnapshot()); // Balance = 0 Inflow = 0 Outflow = 0

        _triggerDepositWithdrawProcess();

        for (uint24 i = 1; i <= childPoolsLength; i++) {
            uint256 childPoolTargetBalance = s_parentPool.exposed_getChildPoolTargetBalance(i);
            assertApproxEqRel(childPoolTargetBalance, _addDecimals(1_000), 1e14);
        }
        assertApproxEqRel(s_parentPool.getTargetBalance(), _addDecimals(1_000), 1e14);
    }

    /** -- Test Full Withdrawal -- */

    function test_recalculateTotalWithdrawalAmountLockedWhenActiveBalanceIsEqTargetBalance()
        public
    {
        _baseSetupWithLPMinting();

        address user1 = _getUsers(1)[0];
        _enterWithdrawalQueue(user1, _takeRebalancerFee(_addDecimals(2_000)));
        _fillChildPoolSnapshots(_addDecimals(1_000));
        _triggerDepositWithdrawProcess();

        uint256 deficit = s_parentPool.getDeficit();
        assertEq(deficit, _addDecimals(1800));
        _fillDeficit(deficit);

        uint256 parentPoolTargetBalanceBefore = s_parentPool.getTargetBalance();
        uint256 parentPoolActiveBalanceBefore = s_parentPool.getActiveBalance();

        assertEq(parentPoolTargetBalanceBefore, parentPoolActiveBalanceBefore);
        assertEq(s_parentPool.getDeficit(), 0);
        assertEq(s_parentPool.getSurplus(), 0);

        _processPendingWithdrawals();

        uint256 parentPoolTargetBalanceAfter = s_parentPool.getTargetBalance();
        uint256 parentPoolActiveBalanceAfter = s_parentPool.getActiveBalance();
        assertEq(parentPoolTargetBalanceAfter, parentPoolTargetBalanceBefore);
        assertEq(parentPoolActiveBalanceAfter, parentPoolActiveBalanceBefore);

        assertEq(s_parentPool.getDeficit(), 0);
        assertEq(s_parentPool.getSurplus(), 0);
    }

    function test_recalculateTargetBalancesWhenFullWithdrawal() public {
        _baseSetupWithLPMinting();

        address[] memory users = _getUsers(5);
        uint256 totalLpBalance;
        for (uint256 i; i < users.length; i++) {
            uint256 userLpBalance = s_lpToken.balanceOf(users[i]);
            _enterWithdrawalQueue(users[i], userLpBalance);
            totalLpBalance += userLpBalance;
        }

        assertEq(totalLpBalance, s_lpToken.totalSupply());

        _fillChildPoolSnapshots(_addDecimals(1_000));
        _triggerDepositWithdrawProcess();

        _fillDeficit(s_parentPool.getDeficit());
        _processPendingWithdrawals();

        assertEq(s_parentPool.getDeficit(), 0);
        assertEq(s_lpToken.totalSupply(), 0);
        assertEq(s_parentPool.getTargetBalance(), 0);
    }

    /** -- Test LP Token amount calculation -- */

    function test_calculateLpTokenAmountInEmptyPool() public {
        vm.startPrank(s_deployer);
        s_parentPool.setMinDepositQueueLength(1);
        s_parentPool.setMinWithdrawalQueueLength(0);
        vm.stopPrank();

        _fillChildPoolSnapshots();

        uint256 lpBalanceBefore = s_lpToken.balanceOf(s_user);
        uint256 amountToDeposit = 100 * USDC_TOKEN_DECIMALS_SCALE;

        vm.prank(s_user);
        s_parentPool.enterDepositQueue(amountToDeposit);

        vm.prank(s_lancaKeeper);
        s_parentPool.triggerDepositWithdrawProcess();

        uint256 lpTokenBalanceAfter = s_lpToken.balanceOf(s_user);

        assertEq(
            lpTokenBalanceAfter - lpBalanceBefore,
            amountToDeposit - s_parentPool.getRebalancerFee(amountToDeposit)
        );
    }

    function test_calculateLpTokenAmountDepositQueueInEmptyPool() public {
        vm.startPrank(s_deployer);
        s_parentPool.setMinDepositQueueLength(3);
        s_parentPool.setMinWithdrawalQueueLength(0);
        vm.stopPrank();

        _fillChildPoolSnapshots();

        uint256 amountToWithdraw = 100 * USDC_TOKEN_DECIMALS_SCALE;

        address[3] memory users = [makeAddr("user1"), makeAddr("user2"), makeAddr("user3")];
        uint256[3] memory balancesBefore = [uint256(0), uint256(0), uint256(0)];

        for (uint256 i; i < users.length; ++i) {
            _mintUsdc(users[i], amountToWithdraw);
            balancesBefore[i] = s_usdc.balanceOf(users[i]);
            _enterDepositQueue(users[i], amountToWithdraw);
        }

        vm.prank(s_lancaKeeper);
        s_parentPool.triggerDepositWithdrawProcess();

        for (uint256 i; i < users.length; ++i) {
            assertEq(balancesBefore[i] - s_usdc.balanceOf(users[i]), amountToWithdraw);
            assertEq(
                s_lpToken.balanceOf(users[i]),
                amountToWithdraw - s_parentPool.getRebalancerFee(amountToWithdraw)
            );
        }
        assertEq(
            s_lpToken.totalSupply(),
            (amountToWithdraw - s_parentPool.getRebalancerFee(amountToWithdraw)) * users.length
        );
    }

    function test_calculateLpWhenDepositWithdrawalQueue() public {
        // deposit amount 100.000000 USDC
        // get LP after deposit -> amountToDeposit - rebalancerFee = 99.990000 LP

        _setMinWithdrawalAmount(_addDecimals(99));

        uint256 lpBalanceBefore = s_lpToken.balanceOf(s_user);
        uint256 amountToDeposit = 100 * USDC_TOKEN_DECIMALS_SCALE; // 100 USDC

        vm.prank(s_user);
        s_parentPool.enterDepositQueue(amountToDeposit);

        _setQueuesLength(0, 0);
        _fillChildPoolSnapshots();
        _triggerDepositWithdrawProcess();

        uint256 lpBalanceAfterDeposit = s_lpToken.balanceOf(s_user);
        uint256 amountToDepositWithFee = amountToDeposit -
            s_parentPool.getRebalancerFee(amountToDeposit);

        assertEq(lpBalanceAfterDeposit, lpBalanceBefore + amountToDepositWithFee);

        // deposit again 100.000000 USDC -> 99.990000 LP
        // withdraw half - 99.990000

        vm.startPrank(s_user);
        s_parentPool.enterDepositQueue(amountToDeposit);

        s_lpToken.approve(address(s_parentPool), type(uint256).max);
        s_parentPool.enterWithdrawalQueue(lpBalanceAfterDeposit);
        vm.stopPrank();

        _fillChildPoolSnapshots();
        _triggerDepositWithdrawProcess();
        _processPendingWithdrawals();

        // final LP balance should be 99.990000

        uint256 lpTokenBalanceAfterDepositWithdraw = s_lpToken.balanceOf(s_user);
        assertApproxEqRel(lpTokenBalanceAfterDepositWithdraw, lpBalanceAfterDeposit, 1e14);
    }

    function test_calculateLPWhenDepositWithdrawalQueueWithInflow() public {
        vm.prank(s_deployer);
        s_parentPool.setLiquidityCap(_addDecimals(15_000));

        // Base setup
        _setSupportedChildPools(9);
        _setQueuesLength(0, 0);
        _mintUsdc(address(s_parentPool), _addDecimals(1_000));
        _setupParentPoolWithBaseExample();

        address[] memory users = _getUsers(5);
        uint256[] memory balancesBefore = _getEmptyBalances(5);
        uint256 initialLpBalancePerUser = _takeRebalancerFee(_addDecimals(2_000));
        uint256 targetBalanceBefore = s_parentPool.getTargetBalance();

        for (uint256 i; i < users.length; i++) {
            // Evenly distribute existing LP tokens among users
            _mintLpToken(users[i], initialLpBalancePerUser);
            balancesBefore[i] = s_lpToken.balanceOf(users[i]);
        }

        uint256 totalSupplyBefore = s_lpToken.totalSupply();

        // Add withdrawal queue for user 0 with 2000 LP tokens
        uint256 withdrawalAmount = initialLpBalancePerUser;
        _enterWithdrawalQueue(users[0], withdrawalAmount);

        _fillChildPoolSnapshots(_addDecimals(1_000));
        _triggerDepositWithdrawProcess();

        // Fill part of the deficit (should not affect on LP calculation)
        uint256 deficit = s_parentPool.getDeficit();
        assertEq(deficit, _addDecimals(1800));
        _fillDeficit(_addDecimals(800));

        // Deposit 2000 USDC for users 1 and 2
        uint256 newDepositAmount = _addDecimals(2_000);
        _mintUsdc(users[1], newDepositAmount);
        _mintUsdc(users[2], newDepositAmount);
        _enterDepositQueue(users[1], newDepositAmount);
        _enterDepositQueue(users[2], newDepositAmount);

        _fillChildPoolSnapshots(_addDecimals(1_000));
        _triggerDepositWithdrawProcess();

        // User 0 should lose LP tokens
        assertEq(
            s_lpToken.balanceOf(users[0]),
            balancesBefore[0] - initialLpBalancePerUser,
            "User0 LP balance should decrease"
        );
        // Users 1 and 2 should get new LP tokens
        assertApproxEqRel(
            s_lpToken.balanceOf(users[1]),
            balancesBefore[1] + _takeRebalancerFee(newDepositAmount),
            1e14, // 0.01% tolerance
            "User1 LP balance should increase"
        );
        assertApproxEqRel(
            s_lpToken.balanceOf(users[2]),
            balancesBefore[2] + _takeRebalancerFee(newDepositAmount),
            1e14,
            "User2 LP balance should increase"
        );
        // Users 3 and 4 should safe LP tokens
        assertEq(
            s_lpToken.balanceOf(users[3]),
            balancesBefore[3],
            "User3 LP balance should not change"
        );
        assertEq(
            s_lpToken.balanceOf(users[4]),
            balancesBefore[4],
            "User4 LP balance should not change"
        );

        assertApproxEqRel(
            s_lpToken.totalSupply(),
            totalSupplyBefore + _takeRebalancerFee(newDepositAmount) * 2,
            1e14
        );
        assertEq(s_lpToken.balanceOf(address(s_parentPool)), withdrawalAmount);

        // Process withdrawals
        _processPendingWithdrawals();

        assertApproxEqRel(
            s_lpToken.totalSupply(),
            totalSupplyBefore + _takeRebalancerFee(newDepositAmount) * 2 - withdrawalAmount,
            1e14
        );

        // Take surplus (should not affect on LP calculation)
        _takeSurplus(_addDecimals(800));

        _enterDepositQueue(users[0], withdrawalAmount);
        _fillChildPoolSnapshots(_addDecimals(1_000));
        _triggerDepositWithdrawProcess();

        // ParentPool should have 0 LP tokens
        assertEq(s_lpToken.balanceOf(address(s_parentPool)), 0);

        assertApproxEqRel(s_lpToken.balanceOf(users[0]), withdrawalAmount, 1e15);

        // 10000 + 4000
        // -2000
        // +2000
        // = 14000
        assertApproxEqRel(
            s_lpToken.totalSupply(),
            totalSupplyBefore +
                _takeRebalancerFee(newDepositAmount) * 2 -
                withdrawalAmount +
                _takeRebalancerFee(withdrawalAmount),
            1e14
        );

        // Target balance should be 400 USDC more (400 * 10 = 4000 USDC total inflow)
        assertApproxEqRel(
            s_parentPool.getTargetBalance() - targetBalanceBefore,
            _addDecimals(400),
            1e15
        );
    }

    function test_calculateLPWhenDepositWithdrawalQueueWithOutflow() public {
        vm.prank(s_deployer);
        s_parentPool.setLiquidityCap(_addDecimals(15_000));

        // Base setup
        _setSupportedChildPools(9);
        _setQueuesLength(0, 0);
        _mintUsdc(address(s_parentPool), _addDecimals(1_000));
        _setupParentPoolWithBaseExample();

        address[] memory users = _getUsers(5);
        uint256[] memory balancesBefore = _getEmptyBalances(5);
        uint256 initialLpBalancePerUser = _takeRebalancerFee(_addDecimals(2_000));

        for (uint256 i; i < users.length; i++) {
            // Evenly distribute existing LP tokens among users
            _mintLpToken(users[i], initialLpBalancePerUser);
            balancesBefore[i] = s_lpToken.balanceOf(users[i]);
        }

        uint256 totalSupplyBefore = s_lpToken.totalSupply();
        uint256 targetBalanceBefore = s_parentPool.getTargetBalance();

        // Add withdrawal queue for users 0 and 1 with 2000 LP tokens for each
        uint256 withdrawalAmount = initialLpBalancePerUser;
        _enterWithdrawalQueue(users[0], withdrawalAmount);
        _enterWithdrawalQueue(users[1], withdrawalAmount);

        _fillChildPoolSnapshots(_addDecimals(1_000));
        _triggerDepositWithdrawProcess();

        // Fill the deficit (should not affect on LP calculation)
        uint256 deficit = s_parentPool.getDeficit();
        assertEq(deficit, _addDecimals(3600));
        _fillDeficit(deficit);

        // Deposit 1000 USDC for user 2
        uint256 newDepositAmount = _addDecimals(1_000);
        _mintUsdc(users[2], newDepositAmount);
        _enterDepositQueue(users[2], newDepositAmount);

        _fillChildPoolSnapshots(_addDecimals(1_000));
        _triggerDepositWithdrawProcess();

        // User 0 should lose LP tokens
        assertEq(
            s_lpToken.balanceOf(users[0]),
            balancesBefore[0] - initialLpBalancePerUser,
            "User0 LP balance should decrease"
        );
        // Users 1 should lose LP tokens
        assertEq(
            s_lpToken.balanceOf(users[1]),
            balancesBefore[1] - initialLpBalancePerUser,
            "User1 LP balance should decrease"
        );
        // User 2 should get new LP tokens
        assertApproxEqRel(
            s_lpToken.balanceOf(users[2]),
            balancesBefore[2] + _takeRebalancerFee(newDepositAmount),
            1e15,
            "User2 LP balance should increase"
        );
        // Users 3 and 4 should safe LP tokens
        assertEq(
            s_lpToken.balanceOf(users[3]),
            balancesBefore[3],
            "User3 LP balance should not change"
        );
        assertEq(
            s_lpToken.balanceOf(users[4]),
            balancesBefore[4],
            "User4 LP balance should not change"
        );

        assertApproxEqRel(
            s_lpToken.totalSupply(),
            totalSupplyBefore + _takeRebalancerFee(newDepositAmount),
            1e15
        );
        assertEq(s_lpToken.balanceOf(address(s_parentPool)), withdrawalAmount * 2);

        // Process withdrawals
        _processPendingWithdrawals();

        assertApproxEqRel(
            s_lpToken.totalSupply(),
            totalSupplyBefore + _takeRebalancerFee(newDepositAmount) - withdrawalAmount * 2,
            1e15
        );

        // Take surplus (should not affect on LP calculation)
        uint256 surplus = s_parentPool.getSurplus();
        _takeSurplus(surplus);

        // Deposit 1000 USDC for user 0
        _enterDepositQueue(users[0], newDepositAmount);
        _fillChildPoolSnapshots(_addDecimals(1_000));
        _triggerDepositWithdrawProcess();

        // ParentPool should have 0 LP tokens
        assertEq(s_lpToken.balanceOf(address(s_parentPool)), 0);

        assertApproxEqRel(
            s_lpToken.balanceOf(users[0]),
            _takeRebalancerFee(newDepositAmount),
            1e15
        );

        // 10000 - 4000
        // +2000
        // = 8000
        assertApproxEqRel(
            s_lpToken.totalSupply(),
            totalSupplyBefore - withdrawalAmount * 2 + _takeRebalancerFee(newDepositAmount) * 2,
            1e15
        );

        // Target balance should be 200 USDC less (200 * 10 = 2000 USDC total outflow)
        assertApproxEqRel(
            targetBalanceBefore - s_parentPool.getTargetBalance(),
            _addDecimals(200),
            1e15
        );
    }

    /** -- Test Liquidity Token amount calculation -- */

    function test_calculateLIQWhenDepositWithdrawalQueueWithInflow() public {
        // Setting pools
        _setLiquidityCap(address(s_parentPool), _addDecimals(15_000));

        _setSupportedChildPools(9);
        _setQueuesLength(0, 0);
        _mintUsdc(address(s_parentPool), _addDecimals(1_000));
        _setupParentPoolWithBaseExample();

        // Mock LP token balance
        address user1 = makeAddr("user1");
        _mintLpToken(address(this), _takeRebalancerFee(_addDecimals(10_000)));
        s_lpToken.transfer(user1, _takeRebalancerFee(_addDecimals(2_000)));
        uint256 usdcBalanceBefore = s_usdc.balanceOf(user1);

        // -- Enter withdrawal queue 1 --
        _enterWithdrawalQueue(user1, _takeRebalancerFee(_addDecimals(500)));

        _fillChildPoolSnapshots(_addDecimals(1_000));
        _triggerDepositWithdrawProcess();

        // -- Fill deficit --
        // after withdrawal 500 USDC, new targetBalance 950 (floor)
        // but temporary targetBalance for ParentPool is 1_450 (950 + 500)
        // current USDC balance is 1_000
        // deficit is 450 USDC (1_450 - 1_000 or targetBalance - activeBalance)
        uint256 deficit = s_parentPool.getDeficit();
        assertEq(deficit, _addDecimals(450));
        _fillDeficit(deficit);

        // -- Enter withdrawal queue 2 --
        _enterWithdrawalQueue(user1, _takeRebalancerFee(_addDecimals(1_500)));

        _fillChildPoolSnapshots(_addDecimals(1_000));
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

        _fillChildPoolSnapshots(_addDecimals(1_000));
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
        assertApproxEqRel(s_parentPool.getTargetBalance(), _addDecimals(1_050), 1e15);
        assertApproxEqRel(s_parentPool.getSurplus(), _addDecimals(900), 1e15);

        _takeSurplus(_addDecimals(450));

        // Final withdrawals
        // user1 can withdraw 2_000 USDC - fee
        _processPendingWithdrawals();
        assertEq(
            s_usdc.balanceOf(user1),
            usdcBalanceBefore + _takeWithdrawalFee(_addDecimals(2_000))
        );
        assertApproxEqRel(s_usdc.balanceOf(address(s_parentPool)), _addDecimals(1500), 1e15);
    }

    function test_calculateLIQWhenDepositWithdrawalQueueWithOutflow() public {
        // Setting pools
        _setLiquidityCap(address(s_parentPool), _addDecimals(15_000));

        _setSupportedChildPools(9);
        _setQueuesLength(0, 0);
        _mintUsdc(address(s_parentPool), _addDecimals(1_000));
        _setupParentPoolWithBaseExample();

        // Mock LP token balance
        address user1 = makeAddr("user1");
        _mintLpToken(address(this), _takeRebalancerFee(_addDecimals(10_000)));
        s_lpToken.transfer(user1, _takeRebalancerFee(_addDecimals(2_000)));
        uint256 usdcBalanceBefore = s_usdc.balanceOf(user1);

        // -- Enter withdrawal queue 1 --
        _enterWithdrawalQueue(user1, _takeRebalancerFee(_addDecimals(1_000)));

        _fillChildPoolSnapshots(_addDecimals(1_000));
        _triggerDepositWithdrawProcess();

        // -- Fill deficit --
        // after withdrawal 1_000 USDC, new targetBalance 900 (floor)
        // but temporary targetBalance for ParentPool is 1_900 (900 + 1_000)
        // current USDC balance is 1_000
        // deficit is 900 USDC (1_900 - 1_000 or targetBalance - activeBalance)
        uint256 deficit = s_parentPool.getDeficit();
        assertEq(deficit, _addDecimals(900));
        vm.prank(s_operator);
        s_parentPool.fillDeficit(_addDecimals(500)); // bit more than half of the deficit

        // -- Enter withdrawal queue 2 --
        _enterWithdrawalQueue(user1, _takeRebalancerFee(_addDecimals(1_000)));

        _fillChildPoolSnapshots(_addDecimals(1_000));
        _triggerDepositWithdrawProcess();

        // // -- Deposit for 2 users --
        address user2 = makeAddr("user2");
        address user3 = makeAddr("user3");
        _mintUsdc(user2, _addDecimals(1_000));
        _mintUsdc(user3, _addDecimals(1_000));

        uint256 coverFee = _addDecimals(1); // add 1 USDC to cover the fee and trigger processInflow
        _enterDepositQueue(user2, _addDecimals(1_000));
        _enterDepositQueue(user3, _addDecimals(500) + coverFee);

        _fillChildPoolSnapshots(_addDecimals(1_000));
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

        vm.startPrank(s_operator);
        s_iouToken.approve(address(s_parentPool), _addDecimals(50));
        s_parentPool.takeSurplus(_addDecimals(50));
        vm.stopPrank();

        // Final withdrawals
        // user1 can withdraw 2_000 USDC - fee
        _processPendingWithdrawals();
        assertEq(
            s_usdc.balanceOf(user1),
            usdcBalanceBefore + _takeWithdrawalFee(_addDecimals(2_000))
        );

        assertGt(s_usdc.balanceOf(address(s_parentPool)), _addDecimals(950));
    }

    function test_calculateLIQWhenDepositWithdrawalQueue() public {
        // example without fees
        // (x3) users deposit 100 USDC -> 100 LP
        // (x2) users withdraw 100 LP -> 100 USDC
        // user1 USDC balance should be equal to user2 USDC balance after withdrawal

        _setMinWithdrawalAmount(_addDecimals(99));

        // ----------- deposit for 3 users -------------
        uint256 amountToDeposit = 100 * USDC_TOKEN_DECIMALS_SCALE;
        address[3] memory users = [makeAddr("user1"), makeAddr("user2"), makeAddr("user3")];

        for (uint256 i; i < users.length; i++) {
            _mintUsdc(users[i], amountToDeposit);
            vm.prank(users[i]);
            s_usdc.approve(address(s_parentPool), type(uint256).max);
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
            assertEq(s_lpToken.balanceOf(users[i]), lpAmountWithFee);
            assertEq(s_usdc.balanceOf(users[i]), 0);
        }

        // ------------ withdraw for 2 users -------------
        for (uint256 i; i < 2; i++) {
            vm.startPrank(users[i]);
            s_lpToken.approve(address(s_parentPool), type(uint256).max);
            s_parentPool.enterWithdrawalQueue(lpAmountWithFee);
            vm.stopPrank();
        }

        _fillChildPoolSnapshots();
        _triggerDepositWithdrawProcess();
        _processPendingWithdrawals();

        uint256[3] memory balanceAfterWithdrawal = [uint256(0), uint256(0), uint256(0)];
        for (uint256 i; i < users.length; i++) {
            balanceAfterWithdrawal[i] = s_usdc.balanceOf(users[i]);
        }

        assertTrue(
            balanceAfterWithdrawal[0] > 0 &&
                balanceAfterWithdrawal[1] > 0 &&
                balanceAfterWithdrawal[2] == 0
        );

        assertEq(balanceAfterWithdrawal[0], balanceAfterWithdrawal[1]);
    }

    /** Test withdrawal process when user in blacklist */

    function test_safeTransferWrapper_RevertsIfNotSelf() public {
        vm.expectRevert(IParentPool.OnlySelf.selector);
        s_parentPool.safeTransferWrapper(address(s_usdc), address(this), _addDecimals(1_000));
    }

    function test_processPendingWithdrawals_WhenTransferFailed() public {
        _baseSetupWithLPMinting();

        address[] memory users = _getUsers(5);
        MockERC20(address(s_usdc)).blacklist(users[4]);

        for (uint256 i; i < users.length; i++) {
            _enterWithdrawalQueue(users[i], _takeRebalancerFee(_addDecimals(2_000)));
        }

        _fillChildPoolSnapshots(_addDecimals(1_000));
        _triggerDepositWithdrawProcess();

        _fillDeficit(_addDecimals(9_000));

        vm.recordLogs();
        _processPendingWithdrawals();
        Vm.Log[] memory entries = vm.getRecordedLogs();

        for (uint256 i; i < entries.length; i++) {
            if (
                entries[i].topics[0] ==
                keccak256(abi.encodePacked("WithdrawalFailed(address,uint256)"))
            ) {
                (address failedUser, uint256 failedAmount) = abi.decode(
                    entries[i].data,
                    (address, uint256)
                );
                assertEq(failedUser, users[4]);
                assertEq(failedAmount, _takeRebalancerFee(_addDecimals(2_000)));
            } else if (
                entries[i].topics[0] ==
                keccak256(abi.encodePacked("WithdrawalCompleted(bytes32,uint256)"))
            ) {
                (uint256 completedAmount) = abi.decode(entries[i].data, (uint256));

                assertEq(completedAmount, _takeRebalancerFee(_addDecimals(2_000)));
            }
        }

        assertEq(s_usdc.balanceOf(users[4]), 0);
        assertApproxEqRel(s_parentPool.getActiveBalance(), _addDecimals(2_000), 1e15);
        assertEq(s_lpToken.totalSupply(), s_lpToken.balanceOf(users[4]));
        assertEq(s_parentPool.getPendingWithdrawalIds().length, 0);

        _mintUsdc(users[0], _addDecimals(2_000));
        _enterDepositQueue(users[0], _addDecimals(2_000));

        _fillChildPoolSnapshots(_addDecimals(1_000));
        _triggerDepositWithdrawProcess();

        assertApproxEqRel(
            s_lpToken.balanceOf(users[0]),
            _takeRebalancerFee(_addDecimals(2_000)),
            1e15
        );
    }

    /** -- Test deposit plus surplus greater than withdrawal -- */

    function test_depositPlusSurplusGreaterThanWithdrawal() public {
        _baseSetupWithLPMinting();

        address[] memory users = _getUsers(3);

        uint256 initialTotalSupply = s_lpToken.totalSupply();
        uint256 initialParentPoolBalance = s_parentPool.getActiveBalance();

        uint256 depositAmount = _addDecimals(1_000);
        _mintUsdc(users[0], depositAmount);
        _mintUsdc(users[1], depositAmount);

        _enterDepositQueue(users[0], depositAmount);
        _enterDepositQueue(users[1], depositAmount);

        uint256 withdrawalAmountLP = _takeRebalancerFee(_addDecimals(1_000));
        _enterWithdrawalQueue(users[2], withdrawalAmountLP);

        _fillChildPoolSnapshots(_addDecimals(1_000));

        uint256 totalDepositAmountAfterFee = _takeRebalancerFee(depositAmount) * 2;

        _triggerDepositWithdrawProcess();
        _processPendingWithdrawals();

        uint256 expectedLpSupplyChange = totalDepositAmountAfterFee - withdrawalAmountLP;
        assertApproxEqRel(
            s_lpToken.totalSupply(),
            initialTotalSupply + expectedLpSupplyChange,
            1e15,
            "LP total supply should increase by net deposit amount"
        );

        uint256 expectedBalanceIncrease = totalDepositAmountAfterFee - withdrawalAmountLP;
        uint256 currentBalance = s_parentPool.getActiveBalance();
        assertApproxEqRel(
            currentBalance,
            initialParentPoolBalance + expectedBalanceIncrease,
            1e15,
            "ParentPool balance should increase by deposit amount after fees"
        );

        // Surplus = activeBalance - targetBalance
        uint256 activeBalance = s_parentPool.getActiveBalance();
        uint256 newTargetBalance = s_parentPool.getTargetBalance();
        uint256 expectedSurplus = activeBalance - newTargetBalance;

        assertEq(
            s_parentPool.getSurplus(),
            expectedSurplus,
            "Surplus should equal activeBalance - targetBalance when positive"
        );

        assertEq(
            s_parentPool.exposed_getRemainingWithdrawalAmount(),
            0,
            "Remaining withdrawal amount should be 0 when surplus covers all withdrawals"
        );
    }

    function test_depositPlusSurplusGreaterThanWithdrawalWithUsersBalances() public {
        _baseSetupWithLPMinting();

        address[] memory users = _getUsers(3);
        uint256 user1lpBalanceBefore = s_lpToken.balanceOf(users[0]);
        uint256 user2lpBalanceBefore = s_lpToken.balanceOf(users[1]);
        uint256 user3lpBalanceBefore = s_lpToken.balanceOf(users[2]);

        uint256 user2UsdcBalanceBefore = s_usdc.balanceOf(users[1]);

        uint256 depositAmount = _addDecimals(1_000);
        _mintUsdc(users[0], depositAmount);
        _mintUsdc(users[1], depositAmount);

        _enterDepositQueue(users[0], depositAmount);
        _enterDepositQueue(users[1], depositAmount);

        uint256 withdrawalAmountLP = _takeRebalancerFee(_addDecimals(1_000));
        _enterWithdrawalQueue(users[2], withdrawalAmountLP);

        _fillChildPoolSnapshots(_addDecimals(1_000));
        _triggerDepositWithdrawProcess();

        uint256 expectedLpPerUser = _takeRebalancerFee(depositAmount);
        assertApproxEqRel(
            s_lpToken.balanceOf(users[0]),
            user1lpBalanceBefore + expectedLpPerUser,
            1e15,
            "User 1 should receive correct LP amount"
        );
        assertApproxEqRel(
            s_lpToken.balanceOf(users[1]),
            user2lpBalanceBefore + expectedLpPerUser,
            1e15,
            "User 2 should receive correct LP amount"
        );

        assertTrue(
            s_parentPool.isReadyToProcessPendingWithdrawals(),
            "System should be ready to process pending withdrawals"
        );

        _processPendingWithdrawals();

        uint256 user2UsdcBalanceAfter = s_usdc.balanceOf(users[2]);
        (uint256 conceroFee, uint256 rebalanceFee) = s_parentPool.getWithdrawalFee(
            _addDecimals(1_000)
        );
        uint256 expectedWithdrawalAmount = _addDecimals(1_000) - (conceroFee + rebalanceFee);

        assertEq(
            user2UsdcBalanceBefore + expectedWithdrawalAmount,
            user2UsdcBalanceAfter,
            "User should receive correct withdrawal amount after fees"
        );
        assertEq(
            s_lpToken.balanceOf(users[2]),
            user3lpBalanceBefore - expectedLpPerUser,
            "User 3 should spend correct LP amount"
        );
    }

    /** -- Test fuzz for deposit/withdrawal with surplus and deficit -- */

    function testFuzz_depositWithdrawalWithSurplus(
        uint256 depositAmountUser1,
        uint256 depositAmountUser2,
        uint256 withdrawalAmountLP,
        uint256 dailyInflow,
        uint256 dailyOutflow
    ) public {
        depositAmountUser1 = bound(depositAmountUser1, _addDecimals(100), _addDecimals(10_000));
        depositAmountUser2 = bound(depositAmountUser2, _addDecimals(100), _addDecimals(5_000));
        withdrawalAmountLP = bound(
            withdrawalAmountLP,
            _addDecimals(100),
            _takeRebalancerFee(_addDecimals(7_000))
        );
        uint256 childPoolBalance = _addDecimals(1_000);
        dailyInflow = bound(dailyInflow, 0, _addDecimals(5_000));
        dailyOutflow = bound(dailyOutflow, 0, _addDecimals(5_000));

        _baseSetupWithLPMinting();

        address[] memory users = _getUsers(3);
        uint256 lpBalanceBefore = s_lpToken.balanceOf(users[0]);

        uint256 totalDepositAfterFee = _takeRebalancerFee(depositAmountUser1) +
            _takeRebalancerFee(depositAmountUser2);
        vm.assume(withdrawalAmountLP <= lpBalanceBefore);
        vm.assume(totalDepositAfterFee > withdrawalAmountLP);

        uint256 expectedBalanceIncrease = totalDepositAfterFee - withdrawalAmountLP;

        uint256 initialParentPoolBalance = s_parentPool.getActiveBalance();

        _mintUsdc(users[0], depositAmountUser1);
        _mintUsdc(users[1], depositAmountUser2);

        _enterDepositQueue(users[0], depositAmountUser1);
        _enterDepositQueue(users[1], depositAmountUser2);
        _enterWithdrawalQueue(users[2], withdrawalAmountLP);

        _fillChildPoolSnapshots(childPoolBalance, dailyInflow, dailyOutflow);
        s_parentPool.exposed_setYesterdayFlow(dailyInflow, dailyOutflow);

        _triggerDepositWithdrawProcess();

        uint256 currentBalance = s_parentPool.getActiveBalance();

        assertApproxEqRel(
            currentBalance,
            initialParentPoolBalance + expectedBalanceIncrease,
            1e15,
            "ParentPool balance should increase by deposit amount after fees"
        );

        assertTrue(s_parentPool.getSurplus() > 0, "Surplus should be positive");

        uint256 activeBalance = s_parentPool.getActiveBalance();
        uint256 newTargetBalance = s_parentPool.getTargetBalance();
        uint256 expectedSurplus = activeBalance - newTargetBalance;

        assertEq(
            s_parentPool.getSurplus(),
            expectedSurplus,
            "Surplus should equal activeBalance - targetBalance when positive"
        );

        assertEq(
            s_parentPool.exposed_getRemainingWithdrawalAmount(),
            0,
            "Remaining withdrawal amount should be 0 when surplus covers all withdrawals"
        );

        assertGt(newTargetBalance, 0, "Target balance should be positive");

        assertGt(
            s_lpToken.balanceOf(users[0]),
            lpBalanceBefore,
            "User 0 should receive new LP tokens"
        );
        assertGt(
            s_lpToken.balanceOf(users[1]),
            lpBalanceBefore,
            "User 1 should receive new LP tokens"
        );
        assertEq(
            s_lpToken.balanceOf(users[2]),
            lpBalanceBefore - withdrawalAmountLP,
            "User 2 should lose LP tokens"
        );

        uint256 user2UsdcBefore = s_usdc.balanceOf(users[2]);
        _processPendingWithdrawals();

        assertEq(
            s_lpToken.balanceOf(address(s_parentPool)),
            0,
            "All withdrawn LP tokens should be burned"
        );

        uint256 user2UsdcAfter = s_usdc.balanceOf(users[2]);
        assertGt(user2UsdcAfter, user2UsdcBefore, "User should receive USDC from withdrawal");
    }

    function testFuzz_depositWithdrawalWithDeficit(
        uint256 depositAmountUser1,
        uint256 withdrawalAmountLPUser2,
        uint256 withdrawalAmountLPUser3,
        uint256 dailyInflow,
        uint256 dailyOutflow
    ) public {
        _baseSetupWithLPMinting();
        address[] memory users = _getUsers(3);

        depositAmountUser1 = bound(depositAmountUser1, _addDecimals(100), _addDecimals(4_000));
        withdrawalAmountLPUser2 = bound(
            withdrawalAmountLPUser2,
            _addDecimals(100),
            s_lpToken.balanceOf(users[1])
        );
        withdrawalAmountLPUser3 = bound(
            withdrawalAmountLPUser3,
            _addDecimals(100),
            s_lpToken.balanceOf(users[2]) / 2
        );
        uint256 childPoolBalance = _addDecimals(1_000);
        dailyInflow = bound(dailyInflow, 0, _addDecimals(5_000));
        dailyOutflow = bound(dailyOutflow, 0, _addDecimals(5_000));

        uint256 totalDepositAfterFee = _takeRebalancerFee(depositAmountUser1);
        vm.assume(totalDepositAfterFee < withdrawalAmountLPUser2 + withdrawalAmountLPUser3);

        uint256 initialParentPoolBalance = s_parentPool.getActiveBalance();

        _mintUsdc(users[0], depositAmountUser1);

        _enterDepositQueue(users[0], depositAmountUser1);
        _enterWithdrawalQueue(users[1], withdrawalAmountLPUser2);
        _enterWithdrawalQueue(users[2], withdrawalAmountLPUser3);

        _fillChildPoolSnapshots(childPoolBalance, dailyInflow, dailyOutflow);
        s_parentPool.exposed_setYesterdayFlow(dailyInflow, dailyOutflow);

        uint256 currentBalance = s_parentPool.getActiveBalance();
        _triggerDepositWithdrawProcess();

        uint256 deficit = s_parentPool.getDeficit();
        assertTrue(deficit > 0, "Deficit should be positive");

        assertEq(
            currentBalance,
            initialParentPoolBalance,
            "ParentPool balance should be equal to initial parent pool balance when deficit is positive"
        );

        uint256 activeBalance = s_parentPool.getActiveBalance();
        uint256 newTargetBalance = s_parentPool.getTargetBalance();
        uint256 expectedDeficit = newTargetBalance - activeBalance;

        assertEq(
            deficit,
            expectedDeficit,
            "Deficit should equal targetBalance - activeBalance when deficit is positive"
        );

        assertEq(
            s_parentPool.exposed_getRemainingWithdrawalAmount(),
            deficit,
            "Remaining withdrawal should be equal to deficit"
        );

        _fillDeficit(s_parentPool.getDeficit());

        activeBalance = s_parentPool.getActiveBalance();
        newTargetBalance = s_parentPool.getTargetBalance();
        assertEq(
            activeBalance,
            newTargetBalance,
            "After fillDeficit, ParentPool balance should be equal to targetBalance"
        );

        uint256 user2UsdcBefore = s_usdc.balanceOf(users[1]);
        uint256 user3UsdcBefore = s_usdc.balanceOf(users[2]);

        _processPendingWithdrawals();

        assertEq(
            s_lpToken.balanceOf(address(s_parentPool)),
            0,
            "All withdrawn LP tokens should be burned"
        );

        assertGt(
            s_usdc.balanceOf(users[1]),
            user2UsdcBefore,
            "User 2 should receive USDC from withdrawal"
        );
        assertGt(
            s_usdc.balanceOf(users[2]),
            user3UsdcBefore,
            "User 3 should receive USDC from withdrawal"
        );
    }

    function testFuzz_DepositArbitration(uint96 depositAmount) public {
        _setLiquidityCap(address(s_parentPool), type(uint256).max);
        vm.assume(depositAmount > s_parentPool.getMinDepositAmount());

        address user2 = makeAddr("user2");

        _setQueuesLength(0, 0);
        deal(address(s_usdc), user2, depositAmount);
        deal(address(s_usdc), s_user, depositAmount);

        vm.startPrank(s_user);
        s_usdc.approve(address(s_parentPool), type(uint256).max);
        s_parentPool.enterDepositQueue(depositAmount);
        vm.stopPrank();

        _fillChildPoolSnapshots();
        _triggerDepositWithdrawProcess();

        vm.startPrank(user2);
        s_usdc.approve(address(s_parentPool), type(uint256).max);
        s_parentPool.enterDepositQueue(depositAmount);
        vm.stopPrank();

        _fillChildPoolSnapshots();
        _triggerDepositWithdrawProcess();

        uint256 user1Withdrawable = s_parentPool.getWithdrawableAmount(
            s_parentPool.getActiveBalance(),
            s_lpToken.balanceOf(s_user)
        );

        uint256 user2Withdrawable = s_parentPool.getWithdrawableAmount(
            s_parentPool.getActiveBalance(),
            s_lpToken.balanceOf(user2)
        );

        console.log(user1Withdrawable);
        console.log(user2Withdrawable);

        console.log(user1Withdrawable - user2Withdrawable);

        assert(user1Withdrawable == user2Withdrawable);
    }
}
