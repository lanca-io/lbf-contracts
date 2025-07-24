// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {ParentPoolBase} from "./base/ParentPoolBase.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract ParentPoolDepositTest is ParentPoolBase {
    uint256 constant DEPOSIT_AMOUNT = 1_000_000e6; // 1M USDC

    function setUp() public override {
        super.setUp();
    }

    function test_EnterDepositQueue() public {
        uint256 initialUserBalance = IERC20(usdc).balanceOf(user);
        uint256 initialPoolBalance = IERC20(usdc).balanceOf(address(parentPool));

        enterDepositQueue(user, DEPOSIT_AMOUNT);

        assertEq(
            IERC20(usdc).balanceOf(user),
            initialUserBalance - DEPOSIT_AMOUNT,
            "User balance should decrease by deposit amount"
        );
        assertEq(
            IERC20(usdc).balanceOf(address(parentPool)),
            initialPoolBalance + DEPOSIT_AMOUNT,
            "Pool balance should increase by deposit amount"
        );
    }
}
