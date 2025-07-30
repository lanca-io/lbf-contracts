// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {LancaTest} from "../LancaTest.sol";
import {DeployMockERC20, MockERC20} from "../scripts/deploy/DeployMockERC20.s.sol";
import {DeployLPToken} from "../scripts/deploy/DeployLPToken.s.sol";
import {DeployParentPool} from "../scripts/deploy/DeployParentPool.s.sol";
import {Vm} from "forge-std/src/Vm.sol";

import {ParentPool} from "../../../contracts/ParentPool/ParentPool.sol";
import {LPToken} from "../../../contracts/ParentPool/LPToken.sol";
import {IOUToken} from "../../../contracts/Rebalancer/IOUToken.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {DeployIOUToken} from "../scripts/deploy/DeployIOUToken.s.sol";

abstract contract ParentPoolBase is LancaTest {
    ParentPool public parentPool;
    LPToken public lpToken;

    function setUp() public virtual {
        DeployMockERC20 deployMockERC20 = new DeployMockERC20();
        usdc = deployMockERC20.deployERC20("USD Coin", "USDC", 6);

        DeployIOUToken deployIOUToken = new DeployIOUToken();
        iouToken = deployIOUToken.deployIOUToken(deployer, address(0));

        DeployLPToken deployLPToken = new DeployLPToken();
        lpToken = LPToken(deployLPToken.deployLPToken(address(this), address(this)));

        DeployParentPool deployParentPool = new DeployParentPool();
        parentPool = ParentPool(
            payable(
                deployParentPool.deployParentPool(
                    usdc,
                    6,
                    address(lpToken),
                    conceroRouter,
                    PARENT_POOL_CHAIN_SELECTOR,
                    address(iouToken)
                )
            )
        );

        lpToken.grantRole(lpToken.MINTER_ROLE(), address(parentPool));
        fundTestAddresses();
        approveUSDCForAll();
    }

    function fundTestAddresses() internal {
        vm.deal(user, 100 ether);
        vm.deal(liquidityProvider, 100 ether);
        vm.deal(operator, 100 ether);
        vm.deal(lancaKeeper, 10 ether);

        vm.startPrank(deployer);
        MockERC20(usdc).mint(user, 10_000_000e6);
        MockERC20(usdc).mint(liquidityProvider, 50_000_000e6);
        MockERC20(usdc).mint(operator, 1_000_000e6);
        vm.stopPrank();
    }

    function approveUSDCForAll() internal {
        vm.prank(user);
        IERC20(usdc).approve(address(parentPool), type(uint256).max);

        vm.prank(liquidityProvider);
        IERC20(usdc).approve(address(parentPool), type(uint256).max);

        vm.prank(operator);
        IERC20(usdc).approve(address(parentPool), type(uint256).max);
    }

    function enterDepositQueue(address depositor, uint256 amount) internal returns (bytes32) {
        vm.prank(depositor);
        vm.recordLogs();
        parentPool.enterDepositQueue(amount);
        Vm.Log[] memory entries = vm.getRecordedLogs();
        return entries[entries.length - 1].topics[1];
    }
}
