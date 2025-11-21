// SPDX-License-Identifier: UNLICENSED
/* solhint-disable func-name-mixedcase */
/* solhint-disable one-contract-per-file */
pragma solidity 0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ICommonErrors} from "contracts/common/interfaces/ICommonErrors.sol";
import {Storage as s} from "contracts/Base/libraries/Storage.sol";
import {IOUToken} from "contracts/Rebalancer/IOUToken.sol";
import {Base} from "contracts/Base/Base.sol";
import {LancaTest} from "../helpers/LancaTest.sol";
import {MockERC20} from "../mocks/MockERC20.sol";

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

    function _handleConceroReceiveBridgeIou(bytes32, uint24, bytes calldata) internal override {}
    function _handleConceroReceiveSnapshot(uint24, bytes calldata) internal override {}
    function _handleConceroReceiveBridgeLiquidity(
        bytes32,
        uint24,
        uint256,
        bytes calldata
    ) internal override {}
    function _handleConceroReceiveUpdateTargetBalance(bytes calldata) internal override {}
}

contract BaseTest is LancaTest {
    TestPoolBase public s_base;

    function setUp() public {
        s_iouToken = new IOUToken(address(this), address(0));

        // Deploy TestPoolBase with mock token
        s_base = new TestPoolBase(
            address(s_usdc),
            s_conceroRouter,
            address(s_iouToken),
            USDC_TOKEN_DECIMALS,
            PARENT_POOL_CHAIN_SELECTOR
        );
    }

    function test_getPoolData_returnsCorrectDeficitAndSurplus() public {
        // Initially, pool should have 0 balance and 0 target balance
        (uint256 deficit, uint256 surplus) = s_base.getPoolData();

        assertEq(deficit, 0, "Initial deficit should be 0");
        assertEq(surplus, 0, "Initial surplus should be 0");

        // Set target balance to 1000 tokens
        s_base.setTargetBalance(1000e6);

        // With 0 active balance, deficit should be 1000e6
        (deficit, surplus) = s_base.getPoolData();
        assertEq(
            deficit,
            1000e6,
            "Deficit should be 1000e6 when target is 1000e6 and balance is 0"
        );
        assertEq(surplus, 0, "Surplus should be 0 when balance is less than target");

        // Mint 500 tokens to the pool
        MockERC20(address(s_usdc)).mint(address(s_base), 500e6);

        // Now deficit should be 500e6
        (deficit, surplus) = s_base.getPoolData();
        assertEq(
            deficit,
            500e6,
            "Deficit should be 500e6 when target is 1000e6 and balance is 500e6"
        );
        assertEq(surplus, 0, "Surplus should be 0 when balance is less than target");

        // Mint another 750 tokens (total 1250e6)
        MockERC20(address(s_usdc)).mint(address(s_base), 750e6);

        // Now surplus should be 250e6
        (deficit, surplus) = s_base.getPoolData();
        assertEq(deficit, 0, "Deficit should be 0 when balance exceeds target");
        assertEq(
            surplus,
            250e6,
            "Surplus should be 250e6 when target is 1000e6 and balance is 1250e6"
        );

        // Set target to exactly match balance
        s_base.setTargetBalance(1250e6);

        // Both deficit and surplus should be 0
        (deficit, surplus) = s_base.getPoolData();
        assertEq(deficit, 0, "Deficit should be 0 when balance equals target");
        assertEq(surplus, 0, "Surplus should be 0 when balance equals target");
    }

    function test_getPoolData_withZeroTargetBalance() public {
        // Ensure target balance is 0
        s_base.setTargetBalance(0);

        // Mint some tokens to the pool
        MockERC20(address(s_usdc)).mint(address(s_base), 1000e6);

        (uint256 deficit, uint256 surplus) = s_base.getPoolData();
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
        s_base.setDstPool(CHILD_POOL_CHAIN_SELECTOR, bytes32(0));
    }

    function test_setDstPool_Success() public {
        bytes32 dstPool = bytes32(uint256(1));

        s_base.setDstPool(CHILD_POOL_CHAIN_SELECTOR, dstPool);
        assertEq(s_base.getDstPool(CHILD_POOL_CHAIN_SELECTOR), dstPool);
    }

    function test_setDstPool_RevertsIfChainSelectorIsSameAsParentPool() public {
        vm.expectRevert(ICommonErrors.InvalidChainSelector.selector);
        s_base.setDstPool(PARENT_POOL_CHAIN_SELECTOR, bytes32(0));
    }

    function test_setDstPool_RevertsIfDstPoolIsZeroAddress() public {
        vm.expectRevert(ICommonErrors.AddressShouldNotBeZero.selector);
        s_base.setDstPool(CHILD_POOL_CHAIN_SELECTOR, bytes32(0));
    }

    function test_setLancaKeeper_Success() public {
        address lancaKeeper = address(1);
        s_base.setLancaKeeper(lancaKeeper);

        assertEq(s_base.getLancaKeeper(), lancaKeeper);
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
        s_base.setLancaKeeper(address(0));
    }

    function test_getTodayStartTimestamp() public {
        vm.warp(block.timestamp + 2 days);

        uint32 todayStartTimestamp = s_base.getTodayStartTimestamp();
        assertEq(todayStartTimestamp, uint32(block.timestamp) / 86400);
    }

    function test_getYesterdayStartTimestamp() public {
        vm.warp(block.timestamp + 2 days);

        uint32 yesterdayStartTimestamp = s_base.getYesterdayStartTimestamp();
        assertEq(yesterdayStartTimestamp, s_base.getTodayStartTimestamp() - 1);
    }

    function testFuzz_setRelayerLib(address relayerLib) public {
        vm.assume(relayerLib != address(0));

        s_base.setRelayerLib(relayerLib);
        assert(s_base.getRelayerLib() == relayerLib);
    }

    function testFuzz_setRelayerLib_RelayerAlreadySet_revert(
        address relayerLib,
        address newRelayerLib
    ) public {
        vm.assume(relayerLib != address(0));
        s_base.setRelayerLib(relayerLib);

        vm.expectRevert(abi.encodeWithSelector(Base.RelayerAlreadySet.selector, relayerLib));
        s_base.setRelayerLib(newRelayerLib);
    }

    function test_setRelayerLib_AddressShouldNotBeZero_revert() public {
        address relayerLib = address(0);

        vm.expectRevert(abi.encodeWithSelector(ICommonErrors.AddressShouldNotBeZero.selector));
        s_base.setRelayerLib(relayerLib);
    }

    function test_setRelayerLib_onlyOwner_revert() public {
        address notOwner = makeAddr("not owner");
        address relayerLib = makeAddr("validatorLib");
        vm.expectRevert(
            abi.encodeWithSelector(
                ICommonErrors.UnauthorizedCaller.selector,
                notOwner,
                s_base.getOwner()
            )
        );
        vm.prank(notOwner);
        s_base.setRelayerLib(relayerLib);
    }

    function testFuzz_removeRelayerLib(address relayerLib) public {
        vm.assume(relayerLib != address(0));

        s_base.setRelayerLib(relayerLib);
        assert(s_base.getRelayerLib() != address(0));

        s_base.removeRelayerLib();
        assert(s_base.getRelayerLib() == address(0));
    }

    function test_removeRelayerLib_RelayerIsNotSet_revert() public {
        vm.expectRevert(abi.encodeWithSelector(Base.RelayerIsNotSet.selector));
        s_base.removeRelayerLib();
    }

    function test_removeRelayerLib_onlyOwner_revert() public {
        address notOwner = makeAddr("not owner");
        vm.expectRevert(
            abi.encodeWithSelector(
                ICommonErrors.UnauthorizedCaller.selector,
                notOwner,
                s_base.getOwner()
            )
        );
        vm.prank(notOwner);
        s_base.removeRelayerLib();
    }

    function testFuzz_setValidatorLib(address validatorLib) public {
        vm.assume(validatorLib != address(0));

        s_base.setValidatorLib(validatorLib);
        assert(s_base.getValidatorLib() == validatorLib);
    }

    function test_setValidatorLib_AddressShouldNotBeZero_revert() public {
        address validatorLib = address(0);

        vm.expectRevert(abi.encodeWithSelector(ICommonErrors.AddressShouldNotBeZero.selector));
        s_base.setValidatorLib(validatorLib);
    }

    function testFuzz_setValidator_ValidatorAlreadySet_revert(
        address validatorLib,
        address newValidatorLib
    ) public {
        vm.assume(validatorLib != address(0));
        s_base.setValidatorLib(validatorLib);

        vm.expectRevert(abi.encodeWithSelector(Base.ValidatorAlreadySet.selector, validatorLib));
        s_base.setValidatorLib(newValidatorLib);
    }

    function test_setValidatorLib_onlyOwner_revert() public {
        address notOwner = makeAddr("not owner");
        address validatorLib = makeAddr("validatorLib");
        vm.expectRevert(
            abi.encodeWithSelector(
                ICommonErrors.UnauthorizedCaller.selector,
                notOwner,
                s_base.getOwner()
            )
        );
        vm.prank(notOwner);
        s_base.setValidatorLib(validatorLib);
    }

    function testFuzz_removeValidatorLib(address validatorLib) public {
        vm.assume(validatorLib != address(0));

        s_base.setValidatorLib(validatorLib);
        assert(s_base.getValidatorLib() != address(0));

        s_base.removeValidatorLib();
        assert(s_base.getValidatorLib() == address(0));
    }

    function test_removeValidatorLib_ValidatorIsNotSet_revert() public {
        vm.expectRevert(abi.encodeWithSelector(Base.ValidatorIsNotSet.selector));
        s_base.removeValidatorLib();
    }

    function test_removeValidatorLib_onlyOwner_revert() public {
        address notOwner = makeAddr("not owner");
        address validatorLib = makeAddr("validatorLib");
        vm.expectRevert(
            abi.encodeWithSelector(
                ICommonErrors.UnauthorizedCaller.selector,
                notOwner,
                s_base.getOwner()
            )
        );
        vm.prank(notOwner);
        s_base.removeValidatorLib();
    }
}
