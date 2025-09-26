// SPDX-License-Identifier: UNLICENSED
/* solhint-disable func-name-mixedcase */
/* solhint-disable one-contract-per-file */
pragma solidity 0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {ICommonErrors} from "contracts/common/interfaces/ICommonErrors.sol";
import {Storage as s} from "contracts/Base/libraries/Storage.sol";
import {IOUToken} from "contracts/Rebalancer/IOUToken.sol";
import {Base, IBase} from "contracts/Base/Base.sol";

import {DeployIOUToken} from "../scripts/deploy/DeployIOUToken.s.sol";
import {DeployMockERC20} from "../scripts/deploy/DeployMockERC20.s.sol";
import {MockERC20} from "../scripts/deploy/DeployMockERC20.s.sol";
import {LancaTest} from "../LancaTest.sol";

// Concrete implementation of Base for testing
contract TestPoolBase is Base {
    using s for s.Base;

    constructor(
        address liquidityToken,
        address conceroRouter,
        address iouToken,
        uint8 liquidityTokenDecimals,
        uint24 chainSelector
    ) Base(liquidityToken, conceroRouter, iouToken, liquidityTokenDecimals, chainSelector) {}

    function setTargetBalance(uint256 newTargetBalance) external {
        s.base().targetBalance = newTargetBalance;
    }

    function setTotalLancaFeeInLiqToken(uint256 newTotalLancaFeeInLiqToken) external {
        s.base().totalLancaFeeInLiqToken = newTotalLancaFeeInLiqToken;
    }

    function _handleConceroReceiveBridgeIou(bytes32, uint24, bytes memory) internal override {}
    function _handleConceroReceiveSnapshot(uint24, bytes memory) internal override {}
    function _handleConceroReceiveBridgeLiquidity(
        bytes32,
        uint24,
        bytes memory
    ) internal override {}
    function _handleConceroReceiveUpdateTargetBalance(bytes memory) internal override {}
}

contract BaseTest is LancaTest {
    TestPoolBase public base;

    function setUp() public {
        DeployMockERC20 deployMockERC20 = new DeployMockERC20();
        usdc = IERC20(deployMockERC20.deployERC20("USD Coin", "USDC", 6));

        DeployIOUToken deployIOUToken = new DeployIOUToken();
        iouToken = IOUToken(deployIOUToken.deployIOUToken(address(this), address(0)));

        // Deploy TestPoolBase with mock token
        base = new TestPoolBase(
            address(usdc),
            conceroRouter,
            address(iouToken),
            6,
            PARENT_POOL_CHAIN_SELECTOR
        );
    }

    function test_getPoolData_returnsCorrectDeficitAndSurplus() public {
        // Initially, pool should have 0 balance and 0 target balance
        (uint256 deficit, uint256 surplus) = base.getPoolData();

        assertEq(deficit, 0, "Initial deficit should be 0");
        assertEq(surplus, 0, "Initial surplus should be 0");

        // Set target balance to 1000 tokens
        base.setTargetBalance(1000e6);

        // With 0 active balance, deficit should be 1000e6
        (deficit, surplus) = base.getPoolData();
        assertEq(
            deficit,
            1000e6,
            "Deficit should be 1000e6 when target is 1000e6 and balance is 0"
        );
        assertEq(surplus, 0, "Surplus should be 0 when balance is less than target");

        // Mint 500 tokens to the pool
        MockERC20(address(usdc)).mint(address(base), 500e6);

        // Now deficit should be 500e6
        (deficit, surplus) = base.getPoolData();
        assertEq(
            deficit,
            500e6,
            "Deficit should be 500e6 when target is 1000e6 and balance is 500e6"
        );
        assertEq(surplus, 0, "Surplus should be 0 when balance is less than target");

        // Mint another 750 tokens (total 1250e6)
        MockERC20(address(usdc)).mint(address(base), 750e6);

        // Now surplus should be 250e6
        (deficit, surplus) = base.getPoolData();
        assertEq(deficit, 0, "Deficit should be 0 when balance exceeds target");
        assertEq(
            surplus,
            250e6,
            "Surplus should be 250e6 when target is 1000e6 and balance is 1250e6"
        );

        // Set target to exactly match balance
        base.setTargetBalance(1250e6);

        // Both deficit and surplus should be 0
        (deficit, surplus) = base.getPoolData();
        assertEq(deficit, 0, "Deficit should be 0 when balance equals target");
        assertEq(surplus, 0, "Surplus should be 0 when balance equals target");
    }

    function test_getPoolData_withZeroTargetBalance() public {
        // Ensure target balance is 0
        base.setTargetBalance(0);

        // Mint some tokens to the pool
        MockERC20(address(usdc)).mint(address(base), 1000e6);

        (uint256 deficit, uint256 surplus) = base.getPoolData();
        assertEq(deficit, 0, "Deficit should be 0 when target is 0");
        assertEq(surplus, 1000e6, "Surplus should be entire balance when target is 0");
    }

    function test_setDstPool_RevertsIfNotOwner() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                ICommonErrors.UnauthorizedCaller.selector,
                address(1),
                address(this)
            )
        );

        vm.prank(address(1));
        base.setDstPool(CHILD_POOL_CHAIN_SELECTOR, address(0));
    }

    function test_setDstPool_Success() public {
        address dstPool = address(1);

        base.setDstPool(CHILD_POOL_CHAIN_SELECTOR, dstPool);
        assertEq(base.getDstPool(CHILD_POOL_CHAIN_SELECTOR), dstPool);
    }

    function test_setDstPool_RevertsIfChainSelectorIsSameAsParentPool() public {
        vm.expectRevert(ICommonErrors.InvalidChainSelector.selector);
        base.setDstPool(PARENT_POOL_CHAIN_SELECTOR, address(0));
    }

    function test_setDstPool_RevertsIfDstPoolIsZeroAddress() public {
        vm.expectRevert(ICommonErrors.AddressShouldNotBeZero.selector);
        base.setDstPool(CHILD_POOL_CHAIN_SELECTOR, address(0));
    }

    function test_setLancaKeeper_Success() public {
        address lancaKeeper = address(1);
        base.setLancaKeeper(lancaKeeper);

        assertEq(base.getLancaKeeper(), lancaKeeper);
    }

    function test_setLancaKeeper_RevertsIfNotOwner() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                ICommonErrors.UnauthorizedCaller.selector,
                address(1),
                address(this)
            )
        );
        vm.prank(address(1));
        base.setLancaKeeper(address(0));
    }

    function test_getTodayStartTimestamp() public {
        vm.warp(block.timestamp + 2 days);

        uint32 todayStartTimestamp = base.getTodayStartTimestamp();
        assertEq(todayStartTimestamp, uint32(block.timestamp) / 86400);
    }

    function test_getYesterdayStartTimestamp() public {
        vm.warp(block.timestamp + 2 days);

        uint32 yesterdayStartTimestamp = base.getYesterdayStartTimestamp();
        assertEq(yesterdayStartTimestamp, base.getTodayStartTimestamp() - 1);
    }

    /* --- Withdraw Lanca Fee --- */

    function test_withdrawLancaFee_RevertsIfNotOwner() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                ICommonErrors.UnauthorizedCaller.selector,
                address(1),
                address(this)
            )
        );
        vm.prank(address(1));
        base.withdrawLancaFee(1000e6);
    }

    function test_withdrawLancaFee_RevertsIfAmountIsZero() public {
        vm.expectRevert(ICommonErrors.AmountIsZero.selector);
        base.withdrawLancaFee(0);
    }

    function test_withdrawLancaFee_RevertsInvalidFeeAmount() public {
        vm.expectRevert(ICommonErrors.InvalidFeeAmount.selector);
        base.withdrawLancaFee(1000e6);
    }

    function test_withdrawLancaFee_Success() public {
        MockERC20(address(usdc)).mint(address(base), 100e6);
        base.setTotalLancaFeeInLiqToken(100e6);

        assertEq(base.getWithdrawableLancaFee(), 100e6);

        vm.expectEmit(false, false, false, true);
        emit IBase.LancaFeeWithdrawn(100e6);

        base.withdrawLancaFee(100e6);

        assertEq(base.getWithdrawableLancaFee(), 0);
        assertEq(IERC20(address(usdc)).balanceOf(address(base)), 0);
        assertEq(IERC20(address(usdc)).balanceOf(address(this)), 100e6);
    }

    /* --- Fee management --- */

    function test_setLpPremiumBps_RevertsIfNotOwner() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                ICommonErrors.UnauthorizedCaller.selector,
                address(1),
                address(this)
            )
        );
        vm.prank(address(1));
        base.setLpPremiumBps(100);
    }

    function test_setLpPremiumBps_Success() public {
        base.setLpPremiumBps(100);
        assertEq(base.getLpPremiumBps(), 100);
    }

    function test_setRebalancerPremiumBps_RevertsIfNotOwner() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                ICommonErrors.UnauthorizedCaller.selector,
                address(1),
                address(this)
            )
        );
        vm.prank(address(1));
        base.setRebalancerPremiumBps(100);
    }

    function test_setRebalancerPremiumBps_Success() public {
        base.setRebalancerPremiumBps(100);
        assertEq(base.getRebalancerPremiumBps(), 100);
    }

    function test_setLancaBridgePremiumBps_RevertsIfNotOwner() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                ICommonErrors.UnauthorizedCaller.selector,
                address(1),
                address(this)
            )
        );
        vm.prank(address(1));
        base.setLancaBridgePremiumBps(100);
    }

    function test_setLancaBridgePremiumBps_Success() public {
        base.setLancaBridgePremiumBps(100);
        assertEq(base.getLancaBridgePremiumBps(), 100);
    }
}
