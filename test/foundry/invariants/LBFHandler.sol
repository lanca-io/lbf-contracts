// SPDX-License-Identifier: UNLICENSED
/* solhint-disable func-name-mixedcase */
pragma solidity 0.8.28;

import {Test} from "forge-std/src/Test.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {ChildPool} from "contracts/ChildPool/ChildPool.sol";
import {ParentPoolHarness} from "../harnesses/ParentPoolHarness.sol";
import {ConceroRouterMockWithCall} from "../mocks/ConceroRouterMockWithCall.sol";
import {Base} from "contracts/Base/Base.sol";

contract LBFHandler is Test {
    ParentPoolHarness internal immutable i_parentPool;
    ChildPool internal immutable i_childPool_1;
    ChildPool internal immutable i_childPool_2;
    ConceroRouterMockWithCall internal immutable i_conceroRouter;

    IERC20 internal immutable i_usdc;
    IERC20 internal immutable i_lp;
    IERC20 internal immutable i_iou;

    address internal immutable i_user;
    address internal immutable i_liquidityProvider;
    address internal immutable i_lancaKeeper;
    address internal immutable i_rebalancer;

    uint24 internal constant PARENT_POOL_CHAIN_SELECTOR = 1000;
    uint24 internal constant CHILD_POOL_CHAIN_SELECTOR_1 = 100;
    uint24 internal constant CHILD_POOL_CHAIN_SELECTOR_2 = 200;

    uint256 public s_totalDeposits;
    uint256 public s_totalWithdrawals;
    bool public s_isLastWithdrawal;

    address[] pools;
    mapping(address => uint24 dstPoolChainSelector) internal i_dstPoolChainSelectors;

    constructor(
        address parentPool,
        address childPool1,
        address childPool2,
        address conceroRouter,
        address usdc,
        address lp,
        address iou,
        address user,
        address liquidityProvider,
        address lancaKeeper,
        address rebalancer
    ) {
        i_parentPool = ParentPoolHarness(payable(parentPool));
        i_childPool_1 = ChildPool(payable(childPool1));
        i_childPool_2 = ChildPool(payable(childPool2));

        i_usdc = IERC20(usdc);
        i_lp = IERC20(lp);
        i_iou = IERC20(iou);
        i_user = user;
        i_liquidityProvider = liquidityProvider;
        i_lancaKeeper = lancaKeeper;
        i_rebalancer = rebalancer;

        pools.push(address(i_parentPool));
        pools.push(address(i_childPool_1));
        pools.push(address(i_childPool_2));

        i_dstPoolChainSelectors[address(i_parentPool)] = PARENT_POOL_CHAIN_SELECTOR;
        i_dstPoolChainSelectors[address(i_childPool_1)] = CHILD_POOL_CHAIN_SELECTOR_1;
        i_dstPoolChainSelectors[address(i_childPool_2)] = CHILD_POOL_CHAIN_SELECTOR_2;

        i_conceroRouter = ConceroRouterMockWithCall(conceroRouter);
    }

    function deposit(uint256 amount) external {
        uint256 usdcBalance = i_usdc.balanceOf(i_liquidityProvider);
        uint256 minDepositAmount = i_parentPool.getMinDepositAmount();

        if (usdcBalance < minDepositAmount) return;
        amount = bound(amount, minDepositAmount, usdcBalance);

        s_totalDeposits += amount;

        vm.prank(i_liquidityProvider);
        i_parentPool.enterDepositQueue(amount);

        _sendSnapshotsToParentPool();
        _triggerDepositWithdrawProcess();
    }

    function withdraw(uint256 amount) external {
        uint256 lpBalance = i_lp.balanceOf(i_liquidityProvider);

        if (lpBalance == 0) return;
        amount = bound(amount, 1, lpBalance);

        if (s_isLastWithdrawal) {
            amount = lpBalance;
        }

        s_totalWithdrawals += amount;

        vm.prank(i_liquidityProvider);
        i_parentPool.enterWithdrawalQueue(amount);

        _sendSnapshotsToParentPool();
        _triggerDepositWithdrawProcess();

        if (!i_parentPool.isReadyToProcessPendingWithdrawals()) {
            _rebalance();
        } else {
            _processPendingWithdrawals();
        }
    }

    function bridge(uint256 srcActorIndexSeed, uint256 dstActorIndexSeed, uint256 amount) external {
        address srcPool = pools[bound(srcActorIndexSeed, 0, pools.length - 1)];
        address dstPool = pools[bound(dstActorIndexSeed, 0, pools.length - 1)];

        if (srcPool == dstPool) return;

        uint256 activeBalance = Base(payable(dstPool)).getActiveBalance();
        if (activeBalance == 0) return;

        amount = bound(amount, 0, activeBalance);
        uint256 userBalance = i_usdc.balanceOf(i_user);
        if (amount > userBalance) {
            amount = userBalance;
        }

        uint256 messageFee = i_parentPool.getBridgeNativeFee(CHILD_POOL_CHAIN_SELECTOR_1, 0);

        vm.startPrank(i_user);
        if (srcPool == address(i_parentPool)) {
            i_conceroRouter.setSrcChainSelector(PARENT_POOL_CHAIN_SELECTOR);
            i_parentPool.bridge{value: messageFee}(
                i_user,
                amount,
                i_dstPoolChainSelectors[dstPool],
                0,
                ""
            );
        } else if (srcPool == address(i_childPool_1)) {
            i_conceroRouter.setSrcChainSelector(CHILD_POOL_CHAIN_SELECTOR_1);
            i_childPool_1.bridge{value: messageFee}(
                i_user,
                amount,
                i_dstPoolChainSelectors[dstPool],
                0,
                ""
            );
        } else {
            i_conceroRouter.setSrcChainSelector(CHILD_POOL_CHAIN_SELECTOR_2);
            i_childPool_2.bridge{value: messageFee}(
                i_user,
                amount,
                i_dstPoolChainSelectors[dstPool],
                0,
                ""
            );
        }
        vm.stopPrank();

        _rebalance();
    }

    function _rebalance() internal {
        vm.startPrank(i_rebalancer);
        _fillDeficits();
        _takeSurpluses();
        vm.stopPrank();
    }

    function _fillDeficits() internal {
        uint256 deficit = i_parentPool.getDeficit();
        uint256 usdcBalance = i_usdc.balanceOf(i_rebalancer);
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
        uint256 iouBalance = i_iou.balanceOf(i_rebalancer);
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
        vm.startPrank(i_lancaKeeper);
        i_conceroRouter.setSrcChainSelector(CHILD_POOL_CHAIN_SELECTOR_1);
        i_childPool_1.sendSnapshotToParentPool();
        i_conceroRouter.setSrcChainSelector(CHILD_POOL_CHAIN_SELECTOR_2);
        i_childPool_2.sendSnapshotToParentPool();
        vm.stopPrank();
    }

    function _triggerDepositWithdrawProcess() internal {
        i_conceroRouter.setSrcChainSelector(PARENT_POOL_CHAIN_SELECTOR);

        vm.prank(i_lancaKeeper);
        i_parentPool.triggerDepositWithdrawProcess();
    }

    function _processPendingWithdrawals() internal {
        vm.prank(i_lancaKeeper);
        i_parentPool.processPendingWithdrawals();
    }

    function setIsLastWithdrawal(bool isLastWithdrawal) external {
        s_isLastWithdrawal = isLastWithdrawal;
    }
}
