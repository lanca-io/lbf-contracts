// SPDX-License-Identifier: UNLICENSED
/* solhint-disable func-name-mixedcase */
pragma solidity 0.8.28;

import {Test} from "forge-std/src/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ChildPool} from "contracts/ChildPool/ChildPool.sol";
import {ParentPoolHarness} from "../harnesses/ParentPoolHarness.sol";
import {ConceroRouterMockWithCall} from "../mocks/ConceroRouterMockWithCall.sol";
import {Base} from "contracts/Base/Base.sol";
import {Rebalancer} from "contracts/Rebalancer/Rebalancer.sol";
import {ILancaBridge} from "contracts/LancaBridge/interfaces/ILancaBridge.sol";
import {MessageCodec} from "@concero/v2-contracts/contracts/common/libraries/MessageCodec.sol";
import {BridgeCodec} from "contracts/common/libraries/BridgeCodec.sol";

contract LBFHandler is Test {
    ParentPoolHarness internal immutable i_parentPool;
    ChildPool internal immutable i_childPool_1;
    ChildPool internal immutable i_childPool_2;
    ConceroRouterMockWithCall internal immutable i_conceroRouter;

    IERC20 internal immutable i_usdc;
    IERC20 internal immutable i_lp;
    IERC20 internal immutable i_iou;
    IERC20 internal immutable i_iouChildPool_1;
    IERC20 internal immutable i_iouChildPool_2;

    uint24 internal constant PARENT_POOL_CHAIN_SELECTOR = 1000;
    uint24 internal constant CHILD_POOL_CHAIN_SELECTOR_1 = 100;
    uint24 internal constant CHILD_POOL_CHAIN_SELECTOR_2 = 200;

    uint256 internal constant BRIDGE_FEE = 0.0001 ether;

    address internal s_user = makeAddr("user");
    address internal s_liquidityProvider = makeAddr("liquidityProvider");
    address internal s_lancaKeeper = makeAddr("lancaKeeper");
    address internal s_rebalancer = makeAddr("rebalancer");

    uint256 public s_totalDeposits;
    uint256 public s_totalWithdrawals;
    bool public s_isLastWithdrawal;

    address[] internal s_pools;
    IERC20[] internal s_iouTokens;
    mapping(address pool => uint24 dstPoolChainSelector) internal s_dstPoolChainSelectors;
    mapping(address pool => IERC20 iouToken) internal s_iouTokensByPool;

    constructor(
        address parentPool,
        address childPool1,
        address childPool2,
        address conceroRouter,
        address usdc,
        address lp,
        address iou,
        address iouChildPool1,
        address iouChildPool2
    ) {
        i_parentPool = ParentPoolHarness(payable(parentPool));
        i_childPool_1 = ChildPool(payable(childPool1));
        i_childPool_2 = ChildPool(payable(childPool2));

        i_usdc = IERC20(usdc);
        i_lp = IERC20(lp);
        i_iou = IERC20(iou);
        i_iouChildPool_1 = IERC20(iouChildPool1);
        i_iouChildPool_2 = IERC20(iouChildPool2);

        s_pools.push(address(i_parentPool));
        s_pools.push(address(i_childPool_1));
        s_pools.push(address(i_childPool_2));

        s_iouTokens.push(i_iou);
        s_iouTokens.push(i_iouChildPool_1);
        s_iouTokens.push(i_iouChildPool_2);

        s_dstPoolChainSelectors[address(i_parentPool)] = PARENT_POOL_CHAIN_SELECTOR;
        s_dstPoolChainSelectors[address(i_childPool_1)] = CHILD_POOL_CHAIN_SELECTOR_1;
        s_dstPoolChainSelectors[address(i_childPool_2)] = CHILD_POOL_CHAIN_SELECTOR_2;
        s_iouTokensByPool[address(i_parentPool)] = i_iou;
        s_iouTokensByPool[address(i_childPool_1)] = i_iouChildPool_1;
        s_iouTokensByPool[address(i_childPool_2)] = i_iouChildPool_2;

        i_conceroRouter = ConceroRouterMockWithCall(conceroRouter);
    }

    function deposit(uint256 amount) external {
        uint256 usdcBalance = i_usdc.balanceOf(s_liquidityProvider);
        uint256 minDepositAmount = i_parentPool.getMinDepositAmount();

        if (usdcBalance < minDepositAmount) return;
        amount = bound(amount, minDepositAmount, usdcBalance);

        s_totalDeposits += amount;

        vm.prank(s_liquidityProvider);
        i_parentPool.enterDepositQueue(amount);

        _sendSnapshotsToParentPool();
        _triggerDepositWithdrawProcess();
    }

    function withdraw(uint256 amount) external {
        uint256 lpBalance = i_lp.balanceOf(s_liquidityProvider);

        if (lpBalance == 0) return;
        amount = bound(amount, 1, lpBalance);

        if (s_isLastWithdrawal) {
            amount = lpBalance;
        }

        s_totalWithdrawals += amount;

        vm.prank(s_liquidityProvider);
        i_parentPool.enterWithdrawalQueue(amount);

        _sendSnapshotsToParentPool();
        _triggerDepositWithdrawProcess();

        if (!i_parentPool.isReadyToProcessPendingWithdrawals()) {
            _fillDeficits();
        } else {
            _processPendingWithdrawals();
        }
    }

    function bridge(uint256 srcActorIndexSeed, uint256 dstActorIndexSeed, uint256 amount) external {
        address srcPool = s_pools[bound(srcActorIndexSeed, 0, s_pools.length - 1)];
        address dstPool = s_pools[bound(dstActorIndexSeed, 0, s_pools.length - 1)];

        if (srcPool == dstPool) return;

        uint256 activeBalance = Base(payable(dstPool)).getActiveBalance();
        if (activeBalance == 0) return;

        amount = bound(amount, 0, activeBalance);
        uint256 userBalance = i_usdc.balanceOf(s_user);
        if (amount > userBalance) {
            amount = userBalance;
        }

        _bridge(srcPool, dstPool, amount);

        _fillDeficits();
    }

    function bridgeIOU(uint256 srcActorIndexSeed, uint256 dstActorIndexSeed) external {
        _takeLocalSurpluses();

        address srcPool = s_pools[bound(srcActorIndexSeed, 0, s_pools.length - 1)];
        address dstPool = s_pools[bound(dstActorIndexSeed, 0, s_pools.length - 1)];

        if (srcPool == dstPool) return;

        uint256 srcIOUBalance = s_iouTokensByPool[srcPool].balanceOf(s_rebalancer);
        uint256 dstIOUBalance = s_iouTokensByPool[dstPool].balanceOf(s_rebalancer);
        uint256 srcSurplus = Base(payable(srcPool)).getSurplus();
        uint256 dstSurplus = Base(payable(dstPool)).getSurplus();

        if (dstSurplus >= srcIOUBalance && srcIOUBalance > 0) {
            _bridgeIOU(srcPool, dstPool, srcIOUBalance);
            _takeLocalSurplus(dstPool, srcIOUBalance, dstSurplus);
        } else if (srcSurplus >= dstIOUBalance && dstIOUBalance > 0) {
            _bridgeIOU(dstPool, srcPool, dstIOUBalance);
            _takeLocalSurplus(srcPool, dstIOUBalance, dstSurplus);
        } else {
            return;
        }
    }

    function _bridge(address srcPool, address dstPool, uint256 amount) internal {
        bytes memory dstChainData = MessageCodec.encodeEvmDstChainData(s_user, 0);
        i_conceroRouter.setSrcChainSelector(s_dstPoolChainSelectors[srcPool]);

        vm.prank(s_user);
        ILancaBridge(srcPool).bridge{value: BRIDGE_FEE}(
            amount,
            s_dstPoolChainSelectors[dstPool],
            dstChainData,
            ""
        );
    }

    function _bridgeIOU(address srcPool, address dstPool, uint256 amount) internal {
        i_conceroRouter.setSrcChainSelector(s_dstPoolChainSelectors[srcPool]);

        vm.prank(s_rebalancer);
        Rebalancer(payable(srcPool)).bridgeIOU{value: BRIDGE_FEE}(
            BridgeCodec.toBytes32(s_rebalancer),
            s_dstPoolChainSelectors[dstPool],
            amount
        );
    }

    function _fillDeficits() internal {
        vm.startPrank(s_rebalancer);

        uint256 deficit = i_parentPool.getDeficit();
        uint256 usdcBalance = i_usdc.balanceOf(s_rebalancer);
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

        vm.stopPrank();
    }

    function _takeLocalSurpluses() internal {
        uint256[] memory surpluses = new uint256[](s_pools.length);
        uint256[] memory iouBalances = new uint256[](s_iouTokens.length);

        for (uint8 i; i < s_pools.length; ++i) {
            surpluses[i] = Base(payable(s_pools[i])).getSurplus();
            iouBalances[i] = s_iouTokens[i].balanceOf(s_rebalancer);
        }

        for (uint8 i; i < s_pools.length; ++i) {
            _takeLocalSurplus(s_pools[i], surpluses[i], iouBalances[i]);
        }
    }

    function _takeLocalSurplus(address pool, uint256 surplus, uint256 iouBalance) internal {
        surplus = surplus > iouBalance ? iouBalance : surplus;
        if (surplus > 0) {
            vm.prank(s_rebalancer);
            Rebalancer(payable(pool)).takeSurplus(surplus);
        }
    }

    function _sendSnapshotsToParentPool() internal {
        vm.startPrank(s_lancaKeeper);
        i_conceroRouter.setSrcChainSelector(CHILD_POOL_CHAIN_SELECTOR_1);
        i_childPool_1.sendSnapshotToParentPool();
        i_conceroRouter.setSrcChainSelector(CHILD_POOL_CHAIN_SELECTOR_2);
        i_childPool_2.sendSnapshotToParentPool();
        vm.stopPrank();
    }

    function _triggerDepositWithdrawProcess() internal {
        i_conceroRouter.setSrcChainSelector(PARENT_POOL_CHAIN_SELECTOR);

        vm.prank(s_lancaKeeper);
        i_parentPool.triggerDepositWithdrawProcess();
    }

    function _processPendingWithdrawals() internal {
        vm.prank(s_lancaKeeper);
        i_parentPool.processPendingWithdrawals();
    }

    function setIsLastWithdrawal(bool isLastWithdrawal) external {
        s_isLastWithdrawal = isLastWithdrawal;
    }
}
