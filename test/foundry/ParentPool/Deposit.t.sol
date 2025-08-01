// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {ParentPoolBase} from "./ParentPoolBase.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract ParentPoolDepositTest is ParentPoolBase {
    uint256 private constant MAX_DEPOSIT_AMOUNT = 1_000_000_000e6;

    function setUp() public override {
        super.setUp();
    }

    function test_EnterDepositQueue(uint256 depositAmount) public {
        //        vm.assume(depositAmount > 0 && depositAmount < MAX_DEPOSIT_AMOUNT);
        //
        //        uint256 initialUserBalance = IERC20(usdc).balanceOf(user);
        //        uint256 initialPoolBalance = IERC20(usdc).balanceOf(address(parentPool));
        //
        //        _enterDepositQueue(user, depositAmount);
        //
        //        assertEq(
        //            IERC20(usdc).balanceOf(user),
        //            initialUserBalance - depositAmount,
        //            "User balance should decrease by deposit amount"
        //        );
        //        assertEq(
        //            IERC20(usdc).balanceOf(address(parentPool)),
        //            initialPoolBalance + depositAmount,
        //            "Pool balance should increase by deposit amount"
        //        );
    }
}
