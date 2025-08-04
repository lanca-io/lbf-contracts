// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {ParentPoolBase} from "./ParentPoolBase.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract ParentPoolDepositWithdrawalTest is ParentPoolBase {
    uint256 private constant MAX_DEPOSIT_AMOUNT = 1_000_000_000e6;

    function setUp() public override {
        super.setUp();
    }

    function test_initialDepositAndUpdateTargetBalances() public {
        //        vm.prank(deployer);
        //        s_parentPool.setTargetWithdrawalQueueLength(0);
        //
        //        _fillDepositWithdrawalQueue(100e6, 0);
        //        _fillChildPoolSnapshots();
        //
        //        vm.warp(NOW_TIMESTAMP);
        //
        //        vm.prank(s_lancaKeeper);
        //        s_parentPool.triggerDepositWithdrawProcess();
    }
}
