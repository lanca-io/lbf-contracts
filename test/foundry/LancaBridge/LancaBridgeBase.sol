// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {LancaTest} from "../LancaTest.sol";
import {DeployMockERC20, MockERC20} from "../scripts/deploy/DeployMockERC20.s.sol";
import {DeployLPToken} from "../scripts/deploy/DeployLPToken.s.sol";
import {DeployIOUToken} from "../scripts/deploy/DeployIOUToken.s.sol";
import {DeployChildPool} from "../scripts/deploy/DeployChildPool.s.sol";
import {DeployParentPool} from "../scripts/deploy/DeployParentPool.s.sol";

import {ChildPool} from "../../../contracts/ChildPool/ChildPool.sol";
import {ParentPool} from "../../../contracts/ParentPool/ParentPool.sol";
import {LPToken} from "../../../contracts/ParentPool/LPToken.sol";
import {IOUToken} from "../../../contracts/Rebalancer/IOUToken.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

abstract contract LancaBridgeBase is LancaTest {
    ChildPool public childPool;
    ParentPool public parentPool;
    LPToken public lpToken;

    function setUp() public virtual {
        DeployMockERC20 deployMockERC20 = new DeployMockERC20();
        usdc = IERC20(deployMockERC20.deployERC20("USD Coin", "USDC", 6));

        DeployIOUToken deployIOUToken = new DeployIOUToken();
        iouToken = IOUToken(deployIOUToken.deployIOUToken(deployer, address(0)));

        DeployLPToken deployLPToken = new DeployLPToken();
        lpToken = LPToken(deployLPToken.deployLPToken(address(this), address(this)));

        DeployChildPool deployChildPool = new DeployChildPool();
        childPool = ChildPool(
            deployChildPool.deployChildPool(
                address(usdc),
                6,
                CHILD_POOL_CHAIN_SELECTOR,
                address(iouToken),
                conceroRouter
            )
        );

        DeployParentPool deployParentPool = new DeployParentPool();
        parentPool = ParentPool(
            payable(
                deployParentPool.deployParentPool(
                    address(usdc),
                    6,
                    address(lpToken),
                    conceroRouter,
                    PARENT_POOL_CHAIN_SELECTOR,
                    address(iouToken),
                    MIN_TARGET_BALANCE
                )
            )
        );

        _addDstPools();
        _fundTestAddresses();
        _approveUSDCForAll();

        // For correct getYesterdayFlow calculation
        vm.warp(block.timestamp + 1 days * 365);
    }

    function _addDstPools() internal {
        vm.startPrank(deployer);
        uint24[] memory dstChainSelectorsForChildPool = new uint24[](1);
        address[] memory dstPoolsForChildPool = new address[](1);

        dstChainSelectorsForChildPool[0] = PARENT_POOL_CHAIN_SELECTOR;
        dstPoolsForChildPool[0] = address(parentPool);
        childPool.addDstPools(dstChainSelectorsForChildPool, dstPoolsForChildPool);

        uint24[] memory dstChainSelectorsForParentPool = new uint24[](1);
        address[] memory dstPoolsForParentPool = new address[](1);

        dstChainSelectorsForParentPool[0] = CHILD_POOL_CHAIN_SELECTOR;
        dstPoolsForParentPool[0] = address(childPool);
        parentPool.addDstPools(dstChainSelectorsForParentPool, dstPoolsForParentPool);
        vm.stopPrank();
    }

    function _fundTestAddresses() internal {
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

    function _approveUSDCForAll() internal {
        vm.prank(user);
        IERC20(usdc).approve(address(childPool), type(uint256).max);

        vm.prank(liquidityProvider);
        IERC20(usdc).approve(address(childPool), type(uint256).max);

        vm.prank(operator);
        IERC20(usdc).approve(address(childPool), type(uint256).max);

        vm.prank(user);
        IERC20(usdc).approve(address(parentPool), type(uint256).max);

        vm.prank(liquidityProvider);
        IERC20(usdc).approve(address(parentPool), type(uint256).max);

        vm.prank(operator);
        IERC20(usdc).approve(address(parentPool), type(uint256).max);
    }

    function _getMessageId(
        uint24 dstChainSelector,
        bool shouldFinaliseSrc,
        address feeToken,
        bytes memory message
    ) internal view returns (bytes32) {
        return
            keccak256(
                abi.encode(block.number, dstChainSelector, shouldFinaliseSrc, feeToken, message)
            );
    }
}
