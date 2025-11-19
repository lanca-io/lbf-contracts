// SPDX-License-Identifier: UNLICENSED
/* solhint-disable func-name-mixedcase */
pragma solidity 0.8.28;

import {Test} from "forge-std/src/Test.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {ChildPool} from "contracts/ChildPool/ChildPool.sol";
import {LPToken} from "contracts/ParentPool/LPToken.sol";
import {IOUToken} from "contracts/Rebalancer/IOUToken.sol";
import {MockERC20} from "contracts/MockERC20/MockERC20.sol";
import {Base} from "contracts/Base/Base.sol";

import {ParentPoolHarness} from "../harnesses/ParentPoolHarness.sol";
import {ConceroRouterMockWithCall} from "../mocks/ConceroRouterMockWithCall.sol";
import {DeployChildPool} from "../scripts/deploy/DeployChildPool.s.sol";
import {DeployParentPool} from "../scripts/deploy/DeployParentPool.s.sol";
import {DeployMockERC20} from "../scripts/deploy/DeployMockERC20.s.sol";
import {DeployIOUToken} from "../scripts/deploy/DeployIOUToken.s.sol";
import {DeployLPToken} from "../scripts/deploy/DeployLPToken.s.sol";

import {LancaTest} from "../LancaTest.sol";

import {console} from "forge-std/src/console.sol";

contract InvariantTestBase is LancaTest {
    ParentPoolHarness public s_parentPool;
    ChildPool public s_childPool_1;
    ChildPool public s_childPool_2;
    ConceroRouterMockWithCall public s_conceroRouterMockWithCall;
    IERC20 public s_usdc;
    IOUToken public s_iouToken;
    LPToken public s_lpToken;

	address public s_rebalancer = makeAddr("rebalancer");

    uint24 public constant CHILD_POOL_CHAIN_SELECTOR_2 = 200;

    // initial balances
    uint256 public constant USER_INITIAL_BALANCE = 10_000e6;
    uint256 public constant LIQUIDITY_PROVIDER_INITIAL_BALANCE = 50_000e6;
    uint256 public constant REBALANCER_INITIAL_BALANCE = 10_000e6;
    uint256 public constant INITIAL_TVL = 10_000e6;
    uint64 public constant MIN_DEPOSIT_AMOUNT = 1e6;
    uint256 public constant LIQUIDITY_CAP =
        LIQUIDITY_PROVIDER_INITIAL_BALANCE + USER_INITIAL_BALANCE;

    function setUp() public virtual {
        s_conceroRouterMockWithCall = new ConceroRouterMockWithCall();

        _deployTokens();
        _deployPools();
        _setDstPools();
        _fundTestAddresses();
        _approveTokensForAll();
        _setLibs();
        _setVars();
        _initialDepositToParentPool();
    }

    function _deployTokens() internal {
        DeployMockERC20 deployMockERC20 = new DeployMockERC20();
        s_usdc = IERC20(deployMockERC20.deployERC20("USD Coin", "USDC", 6));

        DeployIOUToken deployIOUToken = new DeployIOUToken();
        s_iouToken = IOUToken(deployIOUToken.deployIOUToken(deployer, address(0)));

        DeployLPToken deployLPToken = new DeployLPToken();
        s_lpToken = LPToken(deployLPToken.deployLPToken(deployer, deployer));

        vm.label(address(s_usdc), "USDC");
        vm.label(address(s_iouToken), "IOUToken");
        vm.label(address(s_lpToken), "LPToken");
    }

    function _deployPools() internal {
        DeployParentPool deployParentPool = new DeployParentPool();
        s_parentPool = ParentPoolHarness(
            payable(
                deployParentPool.deployParentPool(
                    address(s_usdc),
                    6,
                    address(s_lpToken),
                    address(s_conceroRouterMockWithCall),
                    PARENT_POOL_CHAIN_SELECTOR,
                    address(s_iouToken),
                    MIN_TARGET_BALANCE
                )
            )
        );

        DeployChildPool deployChildPool_1 = new DeployChildPool();
        s_childPool_1 = ChildPool(
            payable(
                deployChildPool_1.deployChildPool(
                    address(s_usdc),
                    6,
                    CHILD_POOL_CHAIN_SELECTOR,
                    address(s_iouToken),
                    address(s_conceroRouterMockWithCall)
                )
            )
        );

        DeployChildPool deployChildPool_2 = new DeployChildPool();
        s_childPool_2 = ChildPool(
            payable(
                deployChildPool_2.deployChildPool(
                    address(s_usdc),
                    6,
                    CHILD_POOL_CHAIN_SELECTOR_2,
                    address(s_iouToken),
                    address(s_conceroRouterMockWithCall)
                )
            )
        );

        vm.label(address(s_childPool_1), "childPool_1");
        vm.label(address(s_childPool_2), "childPool_2");
    }

    function _setDstPools() internal {
        vm.startPrank(deployer);
        s_parentPool.setDstPool(CHILD_POOL_CHAIN_SELECTOR, address(s_childPool_1));
        s_parentPool.setDstPool(CHILD_POOL_CHAIN_SELECTOR_2, address(s_childPool_2));

        s_childPool_1.setDstPool(PARENT_POOL_CHAIN_SELECTOR, address(s_parentPool));
        s_childPool_1.setDstPool(CHILD_POOL_CHAIN_SELECTOR_2, address(s_childPool_2));

        s_childPool_2.setDstPool(PARENT_POOL_CHAIN_SELECTOR, address(s_parentPool));
        s_childPool_2.setDstPool(CHILD_POOL_CHAIN_SELECTOR, address(s_childPool_1));
        vm.stopPrank();
    }

    function _fundTestAddresses() internal {
        vm.deal(user, 100 ether);
        vm.deal(liquidityProvider, 100 ether);
        vm.deal(s_rebalancer, 100 ether);
        vm.deal(s_lancaKeeper, 100 ether);
        vm.deal(address(s_parentPool), 100 ether);
        vm.deal(address(s_childPool_1), 100 ether);
        vm.deal(address(s_childPool_2), 100 ether);

        vm.startPrank(deployer);
        MockERC20(address(s_usdc)).mint(user, USER_INITIAL_BALANCE);
        MockERC20(address(s_usdc)).mint(liquidityProvider, LIQUIDITY_PROVIDER_INITIAL_BALANCE);
        MockERC20(address(s_usdc)).mint(s_rebalancer, REBALANCER_INITIAL_BALANCE);
        vm.stopPrank();
    }

    function _approveTokensForAll() internal {
        vm.startPrank(user);
        IERC20(s_usdc).approve(address(s_childPool_1), type(uint256).max);
        IERC20(s_usdc).approve(address(s_childPool_2), type(uint256).max);
        IERC20(s_usdc).approve(address(s_parentPool), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(liquidityProvider);
        IERC20(s_usdc).approve(address(s_parentPool), type(uint256).max);
        IERC20(s_lpToken).approve(address(s_parentPool), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(s_rebalancer);
        IERC20(s_usdc).approve(address(s_childPool_1), type(uint256).max);
        IERC20(s_usdc).approve(address(s_childPool_2), type(uint256).max);
        IERC20(s_usdc).approve(address(s_parentPool), type(uint256).max);
        IERC20(s_iouToken).approve(address(s_childPool_1), type(uint256).max);
        IERC20(s_iouToken).approve(address(s_childPool_2), type(uint256).max);
        IERC20(s_iouToken).approve(address(s_parentPool), type(uint256).max);
        vm.stopPrank();
    }

    function _setLibs() internal {
        _setRelayerLib(CHILD_POOL_CHAIN_SELECTOR, address(s_childPool_1));
        _setRelayerLib(CHILD_POOL_CHAIN_SELECTOR_2, address(s_childPool_2));
        _setRelayerLib(PARENT_POOL_CHAIN_SELECTOR, address(s_parentPool));

        _setValidatorLibs(CHILD_POOL_CHAIN_SELECTOR, address(s_childPool_1));
        _setValidatorLibs(CHILD_POOL_CHAIN_SELECTOR_2, address(s_childPool_2));
        _setValidatorLibs(PARENT_POOL_CHAIN_SELECTOR, address(s_parentPool));
    }

    function _setVars() internal {
        vm.startPrank(deployer);
        s_parentPool.setMinDepositAmount(MIN_DEPOSIT_AMOUNT);
        s_parentPool.setLancaKeeper(s_lancaKeeper);
        s_parentPool.setLurScoreSensitivity(uint64(5 * LIQ_TOKEN_SCALE_FACTOR));
        s_parentPool.setScoresWeights(
            uint64((7 * LIQ_TOKEN_SCALE_FACTOR) / 10),
            uint64((3 * LIQ_TOKEN_SCALE_FACTOR) / 10)
        );
        s_parentPool.setLiquidityCap(LIQUIDITY_CAP);

        s_childPool_1.setLancaKeeper(s_lancaKeeper);
        s_childPool_2.setLancaKeeper(s_lancaKeeper);

        s_iouToken.grantRole(s_iouToken.MINTER_ROLE(), address(s_parentPool));
        s_iouToken.grantRole(s_iouToken.MINTER_ROLE(), address(s_childPool_1));
        s_iouToken.grantRole(s_iouToken.MINTER_ROLE(), address(s_childPool_2));

        s_lpToken.grantRole(s_lpToken.MINTER_ROLE(), address(s_parentPool));

        vm.stopPrank();
    }

    function _initialDepositToParentPool() internal {
        vm.warp(block.timestamp + 1 days * 365);

        require(
            INITIAL_TVL < s_usdc.balanceOf(liquidityProvider),
            "INITIAL_TVL is greater than liquidity provider balance"
        );

        vm.prank(liquidityProvider);
        s_parentPool.enterDepositQueue(INITIAL_TVL);

        vm.startPrank(s_lancaKeeper);
        s_conceroRouterMockWithCall.setSrcChainSelector(CHILD_POOL_CHAIN_SELECTOR);
        s_childPool_1.sendSnapshotToParentPool();
        s_conceroRouterMockWithCall.setSrcChainSelector(CHILD_POOL_CHAIN_SELECTOR_2);
        s_childPool_2.sendSnapshotToParentPool();
        s_conceroRouterMockWithCall.setSrcChainSelector(PARENT_POOL_CHAIN_SELECTOR);
        s_parentPool.triggerDepositWithdrawProcess();
        vm.stopPrank();

        vm.startPrank(s_rebalancer);
        s_childPool_1.fillDeficit(s_childPool_1.getDeficit());
        s_childPool_2.fillDeficit(s_childPool_2.getDeficit());

        s_parentPool.takeSurplus(s_iouToken.balanceOf(s_rebalancer));
        vm.stopPrank();
    }
}
