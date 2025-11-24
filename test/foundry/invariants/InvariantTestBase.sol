// SPDX-License-Identifier: UNLICENSED
/* solhint-disable func-name-mixedcase */
pragma solidity 0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ChildPool} from "contracts/ChildPool/ChildPool.sol";
import {LPToken} from "contracts/ParentPool/LPToken.sol";
import {IOUToken} from "contracts/Rebalancer/IOUToken.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {Base} from "contracts/Base/Base.sol";
import {ParentPoolHarness} from "../harnesses/ParentPoolHarness.sol";
import {ConceroRouterMockWithCall} from "../mocks/ConceroRouterMockWithCall.sol";
import {LancaTest} from "../helpers/LancaTest.sol";
import {BridgeCodec} from "contracts/common/libraries/BridgeCodec.sol";

contract InvariantTestBase is LancaTest {
    using BridgeCodec for address;

    ParentPoolHarness public s_parentPool;
    ChildPool public s_childPool_1;
    ChildPool public s_childPool_2;
    ConceroRouterMockWithCall public s_conceroRouterMockWithCall;
    LPToken public s_lpToken;
    IOUToken public s_iouTokenChildPool_1;
    IOUToken public s_iouTokenChildPool_2;

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
        s_lpToken = new LPToken(s_deployer, s_deployer);

        s_iouTokenChildPool_1 = new IOUToken(s_deployer, address(0));
        s_iouTokenChildPool_2 = new IOUToken(s_deployer, address(0));

        vm.label(address(s_usdc), "USDC");
        vm.label(address(s_lpToken), "LPToken");
        vm.label(address(s_iouToken), "IOUToken-PP");
        vm.label(address(s_iouTokenChildPool_1), "IOUToken-CP1");
        vm.label(address(s_iouTokenChildPool_2), "IOUToken-CP2");
    }

    function _deployPools() internal {
        vm.startPrank(s_deployer);
        s_parentPool = new ParentPoolHarness(
            address(s_usdc),
            address(s_lpToken),
            address(s_iouToken),
            address(s_conceroRouterMockWithCall),
            PARENT_POOL_CHAIN_SELECTOR,
            MIN_TARGET_BALANCE
        );

        s_childPool_1 = new ChildPool(
            address(s_conceroRouterMockWithCall),
            address(s_iouTokenChildPool_1),
            address(s_usdc),
            CHILD_POOL_CHAIN_SELECTOR,
            PARENT_POOL_CHAIN_SELECTOR
        );

        s_childPool_2 = new ChildPool(
            address(s_conceroRouterMockWithCall),
            address(s_iouTokenChildPool_2),
            address(s_usdc),
            CHILD_POOL_CHAIN_SELECTOR_2,
            PARENT_POOL_CHAIN_SELECTOR
        );

        vm.stopPrank();

        vm.label(address(s_childPool_1), "childPool_1");
        vm.label(address(s_childPool_2), "childPool_2");
    }

    function _setDstPools() internal {
        vm.startPrank(s_deployer);
        s_parentPool.setDstPool(CHILD_POOL_CHAIN_SELECTOR, address(s_childPool_1).toBytes32());
        s_parentPool.setDstPool(CHILD_POOL_CHAIN_SELECTOR_2, address(s_childPool_2).toBytes32());

        s_childPool_1.setDstPool(PARENT_POOL_CHAIN_SELECTOR, address(s_parentPool).toBytes32());
        s_childPool_1.setDstPool(CHILD_POOL_CHAIN_SELECTOR_2, address(s_childPool_2).toBytes32());

        s_childPool_2.setDstPool(PARENT_POOL_CHAIN_SELECTOR, address(s_parentPool).toBytes32());
        s_childPool_2.setDstPool(CHILD_POOL_CHAIN_SELECTOR, address(s_childPool_1).toBytes32());
        vm.stopPrank();
    }

    function _fundTestAddresses() internal {
        vm.deal(s_user, 100 ether);
        vm.deal(s_liquidityProvider, 100 ether);
        vm.deal(s_rebalancer, 100 ether);
        vm.deal(s_lancaKeeper, 100 ether);
        vm.deal(address(s_parentPool), 100 ether);
        vm.deal(address(s_childPool_1), 100 ether);
        vm.deal(address(s_childPool_2), 100 ether);

        vm.startPrank(s_deployer);
        MockERC20(address(s_usdc)).mint(s_user, USER_INITIAL_BALANCE);
        MockERC20(address(s_usdc)).mint(s_liquidityProvider, LIQUIDITY_PROVIDER_INITIAL_BALANCE);
        MockERC20(address(s_usdc)).mint(s_rebalancer, REBALANCER_INITIAL_BALANCE);
        vm.stopPrank();
    }

    function _approveTokensForAll() internal {
        vm.startPrank(s_user);
        IERC20(s_usdc).approve(address(s_childPool_1), type(uint256).max);
        IERC20(s_usdc).approve(address(s_childPool_2), type(uint256).max);
        IERC20(s_usdc).approve(address(s_parentPool), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(s_liquidityProvider);
        IERC20(s_usdc).approve(address(s_parentPool), type(uint256).max);
        IERC20(s_lpToken).approve(address(s_parentPool), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(s_rebalancer);
        IERC20(s_usdc).approve(address(s_childPool_1), type(uint256).max);
        IERC20(s_usdc).approve(address(s_childPool_2), type(uint256).max);
        IERC20(s_usdc).approve(address(s_parentPool), type(uint256).max);
        IERC20(s_iouToken).approve(address(s_parentPool), type(uint256).max);
        IERC20(s_iouTokenChildPool_1).approve(address(s_childPool_1), type(uint256).max);
        IERC20(s_iouTokenChildPool_2).approve(address(s_childPool_2), type(uint256).max);
        vm.stopPrank();
    }

    function _setLibs() internal {
        _setRelayerLib(address(s_childPool_1));
        _setRelayerLib(address(s_childPool_2));
        _setRelayerLib(address(s_parentPool));

        _setValidatorLibs(address(s_childPool_1));
        _setValidatorLibs(address(s_childPool_2));
        _setValidatorLibs(address(s_parentPool));
    }

    function _setVars() internal {
        vm.startPrank(s_deployer);
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
        s_iouTokenChildPool_1.grantRole(
            s_iouTokenChildPool_1.MINTER_ROLE(),
            address(s_childPool_1)
        );
        s_iouTokenChildPool_2.grantRole(
            s_iouTokenChildPool_2.MINTER_ROLE(),
            address(s_childPool_2)
        );

        s_lpToken.grantRole(s_lpToken.MINTER_ROLE(), address(s_parentPool));

        vm.stopPrank();
    }

    function _initialDepositToParentPool() internal {
        vm.warp(block.timestamp + 1 days * 365);

        require(
            INITIAL_TVL < s_usdc.balanceOf(s_liquidityProvider),
            "INITIAL_TVL is greater than liquidity provider balance"
        );

        vm.prank(s_liquidityProvider);
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

        s_conceroRouterMockWithCall.setSrcChainSelector(CHILD_POOL_CHAIN_SELECTOR);
        s_childPool_1.bridgeIOU{value: 0.0001 ether}(
            BridgeCodec.toBytes32(s_rebalancer),
            PARENT_POOL_CHAIN_SELECTOR,
            s_iouTokenChildPool_1.balanceOf(s_rebalancer)
        );

        s_conceroRouterMockWithCall.setSrcChainSelector(CHILD_POOL_CHAIN_SELECTOR_2);
        s_childPool_2.bridgeIOU{value: 0.0001 ether}(
            BridgeCodec.toBytes32(s_rebalancer),
            PARENT_POOL_CHAIN_SELECTOR,
            s_iouTokenChildPool_2.balanceOf(s_rebalancer)
        );

        s_parentPool.takeSurplus(s_iouToken.balanceOf(s_rebalancer));
        vm.stopPrank();
    }
}
