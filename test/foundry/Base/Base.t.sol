// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {LancaTest} from "../LancaTest.sol";
import {Base} from "../../../contracts/Base/Base.sol";
import {Storage as s} from "../../../contracts/Base/libraries/Storage.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {MockERC20} from "../scripts/deploy/DeployMockERC20.s.sol";

// Concrete implementation of Base for testing
//contract TestPoolBase is Base {
//    using s for s.Base;
//
//    constructor(
//        address liquidityToken,
//        uint8 liquidityTokenDecimals,
//        uint24 chainSelector
//    ) Base(liquidityToken, liquidityTokenDecimals, chainSelector) {}
//
//    function setTargetBalance(uint256 newTargetBalance) external {
//        s.base().targetBalance = newTargetBalance;
//    }
//}

contract BaseTest is LancaTest {
    //    TestPoolBase public base;
    //    MockERC20 public mockToken;
    //
    //    function setUp() public {
    //        // Deploy mock ERC20 token with 6 decimals (like USDC)
    //        mockToken = new MockERC20("Test Token", "TEST", 6);
    //
    //        // Deploy TestPoolBase with mock token
    //        base = new TestPoolBase(address(mockToken), 6, PARENT_POOL_CHAIN_SELECTOR);
    //    }
    //
    //    function test_getPoolData_returnsCorrectDeficitAndSurplus() public {
    //        // Initially, pool should have 0 balance and 0 target balance
    //        (uint256 deficit, uint256 surplus) = base.getPoolData();
    //
    //        assertEq(deficit, 0, "Initial deficit should be 0");
    //        assertEq(surplus, 0, "Initial surplus should be 0");
    //
    //        // Set target balance to 1000 tokens
    //        base.setTargetBalance(1000e6);
    //
    //        // With 0 active balance, deficit should be 1000e6
    //        (deficit, surplus) = base.getPoolData();
    //        assertEq(
    //            deficit,
    //            1000e6,
    //            "Deficit should be 1000e6 when target is 1000e6 and balance is 0"
    //        );
    //        assertEq(surplus, 0, "Surplus should be 0 when balance is less than target");
    //
    //        // Mint 500 tokens to the pool
    //        mockToken.mint(address(base), 500e6);
    //
    //        // Now deficit should be 500e6
    //        (deficit, surplus) = base.getPoolData();
    //        assertEq(
    //            deficit,
    //            500e6,
    //            "Deficit should be 500e6 when target is 1000e6 and balance is 500e6"
    //        );
    //        assertEq(surplus, 0, "Surplus should be 0 when balance is less than target");
    //
    //        // Mint another 750 tokens (total 1250e6)
    //        mockToken.mint(address(base), 750e6);
    //
    //        // Now surplus should be 250e6
    //        (deficit, surplus) = base.getPoolData();
    //        assertEq(deficit, 0, "Deficit should be 0 when balance exceeds target");
    //        assertEq(
    //            surplus,
    //            250e6,
    //            "Surplus should be 250e6 when target is 1000e6 and balance is 1250e6"
    //        );
    //
    //        // Set target to exactly match balance
    //        base.setTargetBalance(1250e6);
    //
    //        // Both deficit and surplus should be 0
    //        (deficit, surplus) = base.getPoolData();
    //        assertEq(deficit, 0, "Deficit should be 0 when balance equals target");
    //        assertEq(surplus, 0, "Surplus should be 0 when balance equals target");
    //    }
    //
    //    function test_getPoolData_withZeroTargetBalance() public {
    //        // Ensure target balance is 0
    //        base.setTargetBalance(0);
    //
    //        // Mint some tokens to the pool
    //        mockToken.mint(address(base), 1000e6);
    //
    //        (uint256 deficit, uint256 surplus) = base.getPoolData();
    //        assertEq(deficit, 0, "Deficit should be 0 when target is 0");
    //        assertEq(surplus, 1000e6, "Surplus should be entire balance when target is 0");
    //    }
}
