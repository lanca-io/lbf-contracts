// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {ParentPoolBase} from "./ParentPoolBase.sol";
import {IPoolBase} from "../../../contracts/PoolBase/interfaces/IPoolBase.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IParentPool} from "../../../contracts/ParentPool/interfaces/IParentPool.sol";

import "forge-std/src/console.sol";

contract ParentPoolDepositWithdrawalTest is ParentPoolBase {
    uint256 private constant MAX_DEPOSIT_AMOUNT = 1_000_000_000e6;

    function setUp() public override {
        super.setUp();
        vm.warp(NOW_TIMESTAMP);
    }

    function test_initialDepositAndUpdateTargetBalances(uint256 amountToDepositPerUser) public {
        vm.assume(amountToDepositPerUser > 0 && amountToDepositPerUser < MAX_DEPOSIT_AMOUNT);

        _mintUsdc(user, amountToDepositPerUser * s_parentPool.getTargetDepositQueueLength());

        vm.prank(deployer);
        s_parentPool.setTargetWithdrawalQueueLength(0);

        uint256 initialParentPoolBalance = s_parentPool.getActiveBalance();

        _fillDepositWithdrawalQueue(amountToDepositPerUser, 0);
        _fillChildPoolSnapshots();

        vm.prank(s_lancaKeeper);
        s_parentPool.triggerDepositWithdrawProcess();

        // @dev A fee is charged on part of the amount, not on the entire amount, in order to maintain accuracy
        uint256 totalDeposited;
        for (uint256 i; i < s_parentPool.getTargetDepositQueueLength(); ++i) {
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

    function test_recalculateTargetBalances() public {
        /*
               LBF state before target balances adjustments

               Pool  Balance  targetBalance  Outflow(24h)  Inflow(24h)
               A     120k     100k           80k           60k
               B     85k      100k           150k          140k
               C     95k      100k           200k          180k
               D     110k     100k           40k           50k
               E     90k      100k           90k           70k
        */

        uint256 defaultTargetBalance = 100_000 * LIQ_TOKEN_SCALE_FACTOR;

        _mintUsdc(address(s_parentPool), 110_000 * LIQ_TOKEN_SCALE_FACTOR);
        s_parentPool.exposed_setTargetBalance(defaultTargetBalance);
        s_parentPool.exposed_setYesterdayFlow(
            60_000 * LIQ_TOKEN_SCALE_FACTOR,
            80_000 * LIQ_TOKEN_SCALE_FACTOR
        );

        uint256[3][4] memory childPoolsSetupData = [
            [
                85_000 * LIQ_TOKEN_SCALE_FACTOR,
                140_000 * LIQ_TOKEN_SCALE_FACTOR,
                150_000 * LIQ_TOKEN_SCALE_FACTOR
            ],
            [
                95_000 * LIQ_TOKEN_SCALE_FACTOR,
                180_000 * LIQ_TOKEN_SCALE_FACTOR,
                200_000 * LIQ_TOKEN_SCALE_FACTOR
            ],
            [
                110_000 * LIQ_TOKEN_SCALE_FACTOR,
                50_000 * LIQ_TOKEN_SCALE_FACTOR,
                40_000 * LIQ_TOKEN_SCALE_FACTOR
            ],
            [
                90_000 * LIQ_TOKEN_SCALE_FACTOR,
                70_000 * LIQ_TOKEN_SCALE_FACTOR,
                90_000 * LIQ_TOKEN_SCALE_FACTOR
            ]
        ];

        for (uint256 i; i < _getChildPoolsChainSelectors().length; ++i) {
            s_parentPool.exposed_setChildPoolSnapshot(
                _getChildPoolsChainSelectors()[i],
                _getChildPoolSnapshot(
                    childPoolsSetupData[i][0],
                    childPoolsSetupData[i][1],
                    childPoolsSetupData[i][2]
                )
            );
            s_parentPool.exposed_setChildPoolTargetBalance(
                _getChildPoolsChainSelectors()[i],
                defaultTargetBalance
            );
        }

        uint256 remainingAmount = 10_000 * LIQ_TOKEN_SCALE_FACTOR;
        uint256 amountToDepositPerUser = remainingAmount /
            s_parentPool.getTargetDepositQueueLength();
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

        uint256 expectedParentPoolTargetBalance = (197851016227 * LIQ_TOKEN_SCALE_FACTOR) / 1000000;
        assertEq(s_parentPool.getTargetBalance(), expectedParentPoolTargetBalance);
    }
}
