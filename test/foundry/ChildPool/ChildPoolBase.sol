// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {LancaTest} from "../LancaTest.sol";
import {DeployMockERC20, MockERC20} from "../scripts/deploy/DeployMockERC20.s.sol";
import {DeployIOUToken} from "../scripts/deploy/DeployIOUToken.s.sol";
import {DeployChildPool} from "../scripts/deploy/DeployChildPool.s.sol";

import {ChildPool} from "../../../contracts/ChildPool/ChildPool.sol";
import {IOUToken} from "../../../contracts/Rebalancer/IOUToken.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

abstract contract ChildPoolBase is LancaTest {
    ChildPool public childPool;

    function setUp() public virtual {
        DeployMockERC20 deployMockERC20 = new DeployMockERC20();
        usdc = IERC20(deployMockERC20.deployERC20("USD Coin", "USDC", 6));

        DeployIOUToken deployIOUToken = new DeployIOUToken();
        iouToken = IOUToken(deployIOUToken.deployIOUToken(deployer, address(0)));

        DeployChildPool deployChildPool = new DeployChildPool();
        childPool = ChildPool(
            payable(
                deployChildPool.deployChildPool(
                    address(usdc),
                    6,
                    CHILD_POOL_CHAIN_SELECTOR,
                    address(iouToken),
                    conceroRouter
                )
            )
        );

        fundTestAddresses();
        approveUSDCForAll();

        // For correct getYesterdayFlow calculation
        vm.warp(block.timestamp + 1 days);
    }

    function fundTestAddresses() internal {
        vm.deal(user, 100 ether);
        vm.deal(liquidityProvider, 100 ether);
        vm.deal(operator, 100 ether);

        vm.startPrank(deployer);
        MockERC20(address(usdc)).mint(user, 10_000_000e6);
        MockERC20(address(usdc)).mint(liquidityProvider, 50_000_000e6);
        MockERC20(address(usdc)).mint(operator, 1_000_000e6);
        MockERC20(address(usdc)).mint(address(childPool), INITIAL_POOL_LIQUIDITY);
        vm.stopPrank();
    }

    function approveUSDCForAll() internal {
        vm.prank(user);
        IERC20(usdc).approve(address(childPool), type(uint256).max);

        vm.prank(liquidityProvider);
        IERC20(usdc).approve(address(childPool), type(uint256).max);

        vm.prank(operator);
        IERC20(usdc).approve(address(childPool), type(uint256).max);
    }
}
