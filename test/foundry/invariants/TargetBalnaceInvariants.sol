// SPDX-License-Identifier: UNLICENSED
/* solhint-disable func-name-mixedcase */
pragma solidity 0.8.28;

import {Test} from "forge-std/src/Test.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {ChildPool} from "contracts/ChildPool/ChildPool.sol";
import {ParentPoolHarness} from "../harnesses/ParentPoolHarness.sol";
import {LPToken} from "contracts/ParentPool/LPToken.sol";
import {IOUToken} from "contracts/Rebalancer/IOUToken.sol";
import {ConceroRouterMockWithCall} from "../mocks/ConceroRouterMockWithCall.sol";
import {MockERC20} from "contracts/MockERC20/MockERC20.sol";
import {Base} from "contracts/Base/Base.sol";
import {DeployChildPool} from "../scripts/deploy/DeployChildPool.s.sol";
import {DeployParentPool} from "../scripts/deploy/DeployParentPool.s.sol";
import {DeployMockERC20} from "../scripts/deploy/DeployMockERC20.s.sol";
import {DeployIOUToken} from "../scripts/deploy/DeployIOUToken.s.sol";
import {DeployLPToken} from "../scripts/deploy/DeployLPToken.s.sol";

import {LancaTest} from "../LancaTest.sol";

import {console} from "forge-std/src/console.sol";

contract TargetBalanceHandler is Test {
    ParentPoolHarness internal immutable i_parentPool;
    ChildPool internal immutable i_childPool_1;
    ChildPool internal immutable i_childPool_2;
    ConceroRouterMockWithCall internal immutable i_conceroRouter;
    IERC20 internal immutable i_usdc;
    IERC20 internal immutable i_lp;
    IERC20 internal immutable i_iou;
    address internal immutable i_user;
    address internal immutable i_liquidityProvider;
    uint24 internal immutable i_parentPoolChainSelector;
    uint24 internal immutable i_childPoolChainSelector_1;
    uint24 internal immutable i_childPoolChainSelector_2;

    address internal immutable s_lancaKeeper = makeAddr("lancaKeeper");
    address internal immutable s_operator = makeAddr("operator");

    address[] pools;
    mapping(address => uint24 dstPoolChainSelector) internal i_dstPoolChainSelectors;

    constructor(
        address parentPool,
        address childPool1,
        address childPool2,
        uint24 parentPoolChainSelector,
        uint24 childPoolChainSelector_1,
        uint24 childPoolChainSelector_2,
        address conceroRouter,
        address usdc,
        address lp,
        address iou,
        address user,
        address liquidityProvider
    ) {
        i_parentPool = ParentPoolHarness(payable(parentPool));
        i_childPool_1 = ChildPool(payable(childPool1));
        i_childPool_2 = ChildPool(payable(childPool2));

        i_parentPoolChainSelector = parentPoolChainSelector;
        i_childPoolChainSelector_1 = childPoolChainSelector_1;
        i_childPoolChainSelector_2 = childPoolChainSelector_2;
        i_usdc = IERC20(usdc);
        i_lp = IERC20(lp);
        i_iou = IERC20(iou);
        i_user = user;
        i_liquidityProvider = liquidityProvider;

        pools.push(address(i_parentPool));
        pools.push(address(i_childPool_1));
        pools.push(address(i_childPool_2));

        i_dstPoolChainSelectors[address(i_parentPool)] = parentPoolChainSelector;
        i_dstPoolChainSelectors[address(i_childPool_1)] = childPoolChainSelector_1;
        i_dstPoolChainSelectors[address(i_childPool_2)] = childPoolChainSelector_2;

        i_conceroRouter = ConceroRouterMockWithCall(conceroRouter);
    }

    function deposit(uint256 amount) external {
        uint256 usdcBalance = i_usdc.balanceOf(i_liquidityProvider);
        uint256 minDepositAmount = i_parentPool.getMinDepositAmount();

        if (usdcBalance < minDepositAmount) return;
        amount = bound(amount, minDepositAmount, usdcBalance);

        _etherDepositQueue(amount);
        _sendSnapshotsToParentPool();
        _triggerDepositWithdrawProcess();
    }

    function withdraw(uint256 amount) external {
        uint256 lpBalance = i_lp.balanceOf(i_user);

        if (lpBalance == 0) return;
        amount = bound(amount, 1, lpBalance);

        _enterWithdrawalQueue(amount);

        _sendSnapshotsToParentPool();
        _triggerDepositWithdrawProcess();
        _processPendingWithdrawals();
    }

    function bridge(uint256 srcActorIndexSeed, uint256 dstActorIndexSeed, uint256 amount) external {
        address srcPool = pools[bound(srcActorIndexSeed, 0, pools.length - 1)];
        address dstPool = pools[bound(dstActorIndexSeed, 0, pools.length - 1)];

        if (srcPool == dstPool) return;

        uint256 activeBalance = Base(payable(dstPool)).getActiveBalance();
        if (activeBalance == 0) return;

        amount = bound(amount, 0, activeBalance);
        if (amount > i_usdc.balanceOf(i_user)) {
            amount = i_usdc.balanceOf(i_user);
        }

        console.log("Bridge from, to, amount: ", srcPool, dstPool, amount);

        uint256 messageFee = i_parentPool.getBridgeNativeFee(i_childPoolChainSelector_1, 0);

        vm.startPrank(i_user);
        if (srcPool == address(i_parentPool)) {
            i_conceroRouter.setSrcChainSelector(i_parentPoolChainSelector);
            i_parentPool.bridge{value: messageFee}(
                i_user,
                amount,
                i_dstPoolChainSelectors[dstPool],
                0,
                ""
            );
        } else if (srcPool == address(i_childPool_1)) {
            i_conceroRouter.setSrcChainSelector(i_childPoolChainSelector_1);
            i_childPool_1.bridge{value: messageFee}(
                i_user,
                amount,
                i_dstPoolChainSelectors[dstPool],
                0,
                ""
            );
        } else {
            i_conceroRouter.setSrcChainSelector(i_childPoolChainSelector_2);
            i_childPool_2.bridge{value: messageFee}(
                i_user,
                amount,
                i_dstPoolChainSelectors[dstPool],
                0,
                ""
            );
        }
        vm.stopPrank();

        vm.startPrank(s_operator);
        _fillDeficits();
        _takeSurpluses();
        vm.stopPrank();
    }

    function _fillDeficits() internal {
        uint256 deficit = i_parentPool.getDeficit();
        uint256 usdcBalance = i_usdc.balanceOf(s_lancaKeeper);
        deficit = deficit > usdcBalance ? usdcBalance : deficit;

        if (deficit > 0) {
            i_parentPool.fillDeficit(deficit);
        }

        usdcBalance = usdcBalance - deficit;
        deficit = i_childPool_1.getDeficit();
        deficit = deficit > usdcBalance ? usdcBalance : deficit;
        if (deficit > 0) {
            i_childPool_1.fillDeficit(deficit);
        }

        usdcBalance = usdcBalance - deficit;
        deficit = i_childPool_2.getDeficit();
        deficit = deficit > usdcBalance ? usdcBalance : deficit;
        if (deficit > 0) {
            i_childPool_2.fillDeficit(deficit);
        }
    }

    function _takeSurpluses() internal {
        uint256 surplus = i_parentPool.getSurplus();
        uint256 iouBalance = i_iou.balanceOf(s_lancaKeeper);
        surplus = surplus > iouBalance ? iouBalance : surplus;

        if (surplus > 0) {
            i_parentPool.takeSurplus(surplus);
        }

        iouBalance = iouBalance - surplus;
        surplus = i_childPool_1.getSurplus();
        surplus = surplus > iouBalance ? iouBalance : surplus;

        if (surplus > 0) {
            i_childPool_1.takeSurplus(surplus);
        }

        iouBalance = iouBalance - surplus;
        surplus = i_childPool_2.getSurplus();
        surplus = surplus > iouBalance ? iouBalance : surplus;

        if (surplus > 0) {
            i_childPool_2.takeSurplus(surplus);
        }
    }

    function _sendSnapshotsToParentPool() internal {
        vm.startPrank(s_lancaKeeper);
        i_conceroRouter.setSrcChainSelector(i_childPoolChainSelector_1);
        i_childPool_1.sendSnapshotToParentPool();
        i_conceroRouter.setSrcChainSelector(i_childPoolChainSelector_2);
        i_childPool_2.sendSnapshotToParentPool();
        vm.stopPrank();
    }

    function _triggerDepositWithdrawProcess() internal {
        i_conceroRouter.setSrcChainSelector(i_parentPoolChainSelector);

        vm.prank(s_lancaKeeper);
        i_parentPool.triggerDepositWithdrawProcess();
    }

    function _processPendingWithdrawals() internal {
        vm.prank(s_lancaKeeper);
        i_parentPool.processPendingWithdrawals();
    }

    function _etherDepositQueue(uint256 amount) internal {
        vm.prank(i_liquidityProvider);
        i_parentPool.enterDepositQueue(amount);
    }

    function _enterWithdrawalQueue(uint256 amount) internal {
        vm.prank(i_liquidityProvider);
        i_parentPool.enterWithdrawalQueue(amount);
    }
}

contract TargetBalanceInvariants is LancaTest {
    TargetBalanceHandler public s_targetBalanceHandler;
    ParentPoolHarness public s_parentPool;
    ChildPool public s_childPool_1;
    ChildPool public s_childPool_2;
    ConceroRouterMockWithCall public s_conceroRouterMockWithCall;
    IERC20 public s_usdc;
    IOUToken public s_iouToken;
    LPToken public s_lpToken;

    address public s_user = makeAddr("user");
    address public s_operator = makeAddr("operator");
    address public s_liquidityProvider = makeAddr("liquidityProvider");

    uint24 public constant CHILD_POOL_CHAIN_SELECTOR_2 = 200;

    // initial balances
    uint256 public constant USER_INITIAL_BALANCE = 10_000e6;
    uint256 public constant LIQUIDITY_PROVIDER_INITIAL_BALANCE = 50_000e6;
    uint256 public constant OPERATOR_INITIAL_BALANCE = 10_000e6;
    uint256 public constant INITIAL_TVL = 10_000e6;
    uint64 public constant MIN_DEPOSIT_AMOUNT = 1e6;
    uint256 public constant LIQUIDITY_CAP =
        LIQUIDITY_PROVIDER_INITIAL_BALANCE + USER_INITIAL_BALANCE;

    function setUp() public {
        s_conceroRouterMockWithCall = new ConceroRouterMockWithCall();

        _deployTokens();
        _deployPools();
        _setDstPools();
        _fundTestAddresses();
        _approveTokensForAll();
        _setLibs();
        _setVars();
        _setLiquidityCap();
        _initialDepositToParentPool();

        s_targetBalanceHandler = new TargetBalanceHandler(
            address(s_parentPool),
            address(s_childPool_1),
            address(s_childPool_2),
            PARENT_POOL_CHAIN_SELECTOR,
            CHILD_POOL_CHAIN_SELECTOR,
            CHILD_POOL_CHAIN_SELECTOR_2,
            address(s_conceroRouterMockWithCall),
            address(s_usdc),
            address(s_lpToken),
            address(s_iouToken),
            address(s_user),
            s_liquidityProvider
        );

        bytes4[] memory selectors = new bytes4[](5);
        selectors[0] = TargetBalanceHandler.deposit.selector;
        selectors[1] = TargetBalanceHandler.withdraw.selector;
        selectors[2] = TargetBalanceHandler.bridge.selector;
        selectors[3] = TargetBalanceHandler.bridge.selector;
        selectors[4] = TargetBalanceHandler.bridge.selector;

        targetContract(address(s_targetBalanceHandler));
        targetSelector(FuzzSelector({addr: address(s_targetBalanceHandler), selectors: selectors}));
    }

    function invariant_totalTargetBalanceAlwaysLessOrEqualToActiveBalance() public view {
        uint256 parentPoolTargetBalance = s_parentPool.getTargetBalance();
        uint256 childPoolTargetBalance_1 = s_childPool_1.getTargetBalance();
        uint256 childPoolTargetBalance_2 = s_childPool_2.getTargetBalance();
        uint256 parentPoolActiveBalance = s_parentPool.getActiveBalance();
        uint256 childPoolActiveBalance_1 = s_childPool_1.getActiveBalance();
        uint256 childPoolActiveBalance_2 = s_childPool_2.getActiveBalance();

        uint256 totalTargetBalance = parentPoolTargetBalance +
            childPoolTargetBalance_1 +
            childPoolTargetBalance_2;
        uint256 totalActiveBalance = parentPoolActiveBalance +
            childPoolActiveBalance_1 +
            childPoolActiveBalance_2;

        assert(totalTargetBalance <= totalActiveBalance);
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
        vm.deal(s_user, 100 ether);
        vm.deal(s_liquidityProvider, 100 ether);
        vm.deal(s_operator, 100 ether);
        vm.deal(s_lancaKeeper, 100 ether);
        vm.deal(address(s_parentPool), 100 ether);
        vm.deal(address(s_childPool_1), 100 ether);
        vm.deal(address(s_childPool_2), 100 ether);

        vm.startPrank(deployer);
        MockERC20(address(s_usdc)).mint(s_user, USER_INITIAL_BALANCE);
        MockERC20(address(s_usdc)).mint(s_liquidityProvider, LIQUIDITY_PROVIDER_INITIAL_BALANCE);
        MockERC20(address(s_usdc)).mint(s_operator, OPERATOR_INITIAL_BALANCE);
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

        vm.startPrank(s_operator);
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

        vm.startPrank(s_operator);
        s_childPool_1.fillDeficit(s_childPool_1.getDeficit());
        s_childPool_2.fillDeficit(s_childPool_2.getDeficit());

        s_parentPool.takeSurplus(s_iouToken.balanceOf(s_operator));
        vm.stopPrank();
    }

    function _setLiquidityCap() internal {
        vm.prank(deployer);
        s_parentPool.setLiquidityCap(LIQUIDITY_CAP);
    }
}
