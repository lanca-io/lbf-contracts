// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {IConceroRouter} from "@concero/v2-contracts/contracts/interfaces/IConceroRouter.sol";
import {MessageCodec} from "@concero/v2-contracts/contracts/common/libraries/MessageCodec.sol";
import {LancaTest} from "../helpers/LancaTest.sol";
import {IBase} from "../../../contracts/Base/interfaces/IBase.sol";
import {ChildPool} from "../../../contracts/ChildPool/ChildPool.sol";
import {IOUToken} from "../../../contracts/Rebalancer/IOUToken.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {MockERC20} from "../mocks/MockERC20.sol";

abstract contract ChildPoolBase is LancaTest {
    ChildPool public s_childPool;

    function setUp() public virtual {
        vm.prank(s_deployer);
        s_childPool = new ChildPool(
            address(s_conceroRouter),
            address(s_iouToken),
            address(s_usdc),
            CHILD_POOL_CHAIN_SELECTOR,
            PARENT_POOL_CHAIN_SELECTOR,
            LIQUIDITY_TOKEN_GAS_OVERHEAD
        );
        s_childPool.initialize(s_deployer, s_lancaKeeper);

        _fundTestAddresses();
        _approveUSDCForAll();
        _setLibs();
        _setDstPool();

        // For correct getYesterdayFlow calculation
        vm.warp(block.timestamp + 1 days);
    }

    function _fundTestAddresses() internal {
        vm.deal(s_user, 100 ether);
        vm.deal(s_liquidityProvider, 100 ether);
        vm.deal(s_operator, 100 ether);

        vm.startPrank(s_deployer);
        MockERC20(address(s_usdc)).mint(s_user, 10_000_000e6);
        MockERC20(address(s_usdc)).mint(s_liquidityProvider, 50_000_000e6);
        MockERC20(address(s_usdc)).mint(s_operator, 1_000_000e6);
        MockERC20(address(s_usdc)).mint(address(s_childPool), INITIAL_POOL_LIQUIDITY);
        vm.stopPrank();
    }

    function _approveUSDCForAll() internal {
        vm.prank(s_user);
        IERC20(s_usdc).approve(address(s_childPool), type(uint256).max);

        vm.prank(s_liquidityProvider);
        IERC20(s_usdc).approve(address(s_childPool), type(uint256).max);

        vm.prank(s_operator);
        IERC20(s_usdc).approve(address(s_childPool), type(uint256).max);
    }

    function _setLibs() internal {
        _setRelayerLib(address(s_childPool));
        _setValidatorLibs(address(s_childPool));
    }

    function _setDstPool() internal {
        vm.prank(s_deployer);
        s_childPool.setDstPool(PARENT_POOL_CHAIN_SELECTOR, bytes32(bytes20(s_mockParentPool)));
    }
}
