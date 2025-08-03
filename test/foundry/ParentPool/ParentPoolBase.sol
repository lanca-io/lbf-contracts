// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import "../harnesses/ParentPoolHarness.sol";
import {DeployIOUToken} from "../scripts/deploy/DeployIOUToken.s.sol";
import {DeployLPToken} from "../scripts/deploy/DeployLPToken.s.sol";
import {DeployMockERC20, MockERC20} from "../scripts/deploy/DeployMockERC20.s.sol";
import {DeployParentPool} from "../scripts/deploy/DeployParentPool.s.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IOUToken} from "../../../contracts/Rebalancer/IOUToken.sol";
import {LPToken} from "../../../contracts/ParentPool/LPToken.sol";
import {LancaTest} from "../LancaTest.sol";
import {ParentPool} from "../../../contracts/ParentPool/ParentPool.sol";
import {Vm} from "forge-std/src/Vm.sol";

abstract contract ParentPoolBase is LancaTest {
    uint16 internal constant DEFAULT_TARGET_QUEUE_LENGTH = 5;

    ParentPoolHarness public parentPool;
    LPToken public lpToken;

    function setUp() public virtual {
        DeployMockERC20 deployMockERC20 = new DeployMockERC20();
        usdc = IERC20(deployMockERC20.deployERC20("USD Coin", "USDC", 6));

        DeployIOUToken deployIOUToken = new DeployIOUToken();
        iouToken = deployIOUToken.deployIOUToken(deployer, address(0));

        DeployLPToken deployLPToken = new DeployLPToken();
        lpToken = LPToken(deployLPToken.deployLPToken(address(this), address(this)));

        DeployParentPool deployParentPool = new DeployParentPool();
        parentPool = ParentPoolHarness(
            payable(
                deployParentPool.deployParentPool(
                    address(usdc),
                    6,
                    address(lpToken),
                    conceroRouter,
                    PARENT_POOL_CHAIN_SELECTOR,
                    address(iouToken)
                )
            )
        );

        lpToken.grantRole(lpToken.MINTER_ROLE(), address(parentPool));
        _fundTestAddresses();
        _approveUSDCForAll();
        _setQueuesLength();
    }

    /* HELPER FUNCTIONS */

    function _fundTestAddresses() internal {
        vm.deal(user, 100 ether);
        vm.deal(liquidityProvider, 100 ether);
        vm.deal(operator, 100 ether);
        vm.deal(s_lbfKeeper, 10 ether);

        vm.startPrank(deployer);
        MockERC20(address(usdc)).mint(user, 10_000_000e6);
        MockERC20(address(usdc)).mint(liquidityProvider, 50_000_000e6);
        MockERC20(address(usdc)).mint(operator, 1_000_000e6);
        vm.stopPrank();
    }

    function _approveUSDCForAll() internal {
        vm.prank(user);
        usdc.approve(address(parentPool), type(uint256).max);

        vm.prank(liquidityProvider);
        usdc.approve(address(parentPool), type(uint256).max);

        vm.prank(operator);
        usdc.approve(address(parentPool), type(uint256).max);
    }

    function _enterDepositQueue(address depositor, uint256 amount) internal returns (bytes32) {
        vm.prank(depositor);
        vm.recordLogs();
        parentPool.enterDepositQueue(amount);
        Vm.Log[] memory entries = vm.getRecordedLogs();
        return entries[entries.length - 1].topics[1];
    }

    function _enterWithdrawalQueue(address depositor, uint256 amount) internal returns (bytes32) {
        vm.prank(depositor);
        vm.recordLogs();
        parentPool.enterWithdrawQueue(amount);
        Vm.Log[] memory entries = vm.getRecordedLogs();
        return entries[entries.length - 1].topics[1];
    }

    function _setQueuesLength() internal {
        vm.startPrank(deployer);
        parentPool.setTargetDepositQueueLength(DEFAULT_TARGET_QUEUE_LENGTH);
        parentPool.setTargetWithdrawalQueueLength(DEFAULT_TARGET_QUEUE_LENGTH);
        vm.stopPrank();
    }

    function _fillDepositWithdrawalQueue(
        uint256 totalDepositAmount,
        uint256 totalWithdrawalAmount
    ) internal {
        for (uint256 i; i < parentPool.getTargetDepositQueueLength(); ++i) {
            _enterDepositQueue(user, totalDepositAmount / parentPool.getTargetDepositQueueLength());
        }

        for (uint256 i; i < parentPool.getTargetWithdrawalQueueLength(); ++i) {
            _enterWithdrawalQueue(
                user,
                totalWithdrawalAmount / parentPool.getTargetWithdrawalQueueLength()
            );
        }
    }

    /* MINT FUNCTIONS */

    function _mintUsdc(address receiver, uint256 amount) internal {
        vm.prank(deployer);
        MockERC20(address(usdc)).mint(receiver, amount);
    }
}
