// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {ParentPoolBase} from "./ParentPoolBase.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IParentPool} from "../../../contracts/ParentPool/interfaces/IParentPool.sol";
import "forge-std/src/console.sol";

contract ParentPoolDepositWithdrawalTest is ParentPoolBase {
    uint256 private constant MAX_DEPOSIT_AMOUNT = 1_000_000_000e6;

    function setUp() public override {
        super.setUp();
    }

    function test_initialDepositAndUpdateTargetBalances(uint256 amountToDepositPerUser) public {
        vm.assume(amountToDepositPerUser > 0 && amountToDepositPerUser < MAX_DEPOSIT_AMOUNT);
        vm.warp(NOW_TIMESTAMP);

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
        //        uint256 defaultTargetBalance = 100_000e6;
        //
        //        _mintUsdc(s_parentPool, 110_000e6);
        //        s_parentPool.exposed_setTargetBalance(defaultTargetBalance);
        //
        //        s_parentPool.exposed_setChildPoolSnapshot(
        //            childPoolChainSelector_1,
        //            IParentPool.ChildPoolSnapshot({
        //                timestamp: NOW_TIMESTAMP,
        //                balance: 85_000e6,
        //                iouTotalReceived: 0,
        //                iouTotalSent: 0,
        //                iouTotalSupply: 0,
        //                dailyFlow: IBase.sol.LiqTokenDailyFlow({inflow: 140_000e6, outflow: 150_000e6})
        //            })
        //        );
        //        s_parentPool.exposed_getChildPoolTargetBalance(
        //            childPoolChainSelector_1,
        //            defaultTargetBalance
        //        );
        //
        //        s_parentPool.exposed_setChildPoolSnapshot(
        //            childPoolChainSelector_2,
        //            IParentPool.ChildPoolSnapshot({
        //                timestamp: NOW_TIMESTAMP,
        //                balance: 85_000e6,
        //                iouTotalReceived: 0,
        //                iouTotalSent: 0,
        //                iouTotalSupply: 0,
        //                dailyFlow: IBase.sol.LiqTokenDailyFlow({inflow: 140_000e6, outflow: 150_000e6})
        //            })
        //        );
        //        s_parentPool.exposed_getChildPoolTargetBalance(
        //            childPoolChainSelector_2,
        //            defaultTargetBalance
        //        );
    }
}
