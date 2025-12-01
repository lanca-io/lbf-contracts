// SPDX-License-Identifier: UNLICENSED
/* solhint-disable func-name-mixedcase */
pragma solidity 0.8.28;

import {Test} from "forge-std/src/Test.sol";

import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {MessageCodec} from "@concero/v2-contracts/contracts/common/libraries/MessageCodec.sol";

import {BridgeCodec} from "contracts/common/libraries/BridgeCodec.sol";
import {Decimals} from "contracts/common/libraries/Decimals.sol";
import {ILancaBridge} from "contracts/LancaBridge/interfaces/ILancaBridge.sol";
import {Base} from "contracts/Base/Base.sol";
import {ChildPool} from "contracts/ChildPool/ChildPool.sol";
import {Rebalancer} from "contracts/Rebalancer/Rebalancer.sol";

import {ConceroRouterMockWithCall} from "../mocks/ConceroRouterMockWithCall.sol";
import {ParentPoolHarness} from "../harnesses/ParentPoolHarness.sol";

contract LBFHandler is Test {
    using Decimals for uint256;

    ParentPoolHarness internal immutable i_parentPool;
    ChildPool internal immutable i_childPool_1;
    ChildPool internal immutable i_childPool_2;
    ConceroRouterMockWithCall internal immutable i_conceroRouter;

    IERC20 internal immutable i_usdc;
    IERC20 internal immutable i_usdcWithDec8ChildPool_1;
    IERC20 internal immutable i_usdcWithDec18ChildPool_2;
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

    address[] internal s_pools;
    IERC20[] internal s_iouTokens;

    struct Token {
        IERC20 token;
        uint8 decimals;
    }

    mapping(address pool => uint256 lpFeeAcc) public s_lpFeeAccByPool;

    mapping(address pool => uint24 dstPoolChainSelector) internal s_dstPoolChainSelectors;
    mapping(address pool => Token iouToken) internal s_iouTokensByPool;
    mapping(address pool => Token usdcToken) internal s_usdcTokensByPool;

    constructor(
        address parentPool,
        address childPool1,
        address childPool2,
        address conceroRouter,
        address usdc,
        address usdcWithDec8ChildPool1,
        address usdcWithDec18ChildPool2,
        address lp,
        address iou,
        address iouChildPool1,
        address iouChildPool2
    ) {
        i_parentPool = ParentPoolHarness(payable(parentPool));
        i_childPool_1 = ChildPool(payable(childPool1));
        i_childPool_2 = ChildPool(payable(childPool2));

        i_usdc = IERC20(usdc);
        i_usdcWithDec8ChildPool_1 = IERC20(usdcWithDec8ChildPool1);
        i_usdcWithDec18ChildPool_2 = IERC20(usdcWithDec18ChildPool2);

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

        s_iouTokensByPool[address(i_parentPool)] = _getToken(i_iou);
        s_iouTokensByPool[address(i_childPool_1)] = _getToken(i_iouChildPool_1);
        s_iouTokensByPool[address(i_childPool_2)] = _getToken(i_iouChildPool_2);

        s_usdcTokensByPool[address(i_parentPool)] = _getToken(i_usdc);
        s_usdcTokensByPool[address(i_childPool_1)] = _getToken(i_usdcWithDec8ChildPool_1);
        s_usdcTokensByPool[address(i_childPool_2)] = _getToken(i_usdcWithDec18ChildPool_2);

        i_conceroRouter = ConceroRouterMockWithCall(conceroRouter);
    }

    function deposit(uint256 amount) external {
        uint256 usdcBalance = i_usdc.balanceOf(s_liquidityProvider);
        uint256 minDepositAmount = i_parentPool.getMinDepositAmount();

        if (usdcBalance < minDepositAmount) return;
        amount = bound(amount, minDepositAmount, usdcBalance);

        vm.prank(s_liquidityProvider);
        i_parentPool.enterDepositQueue(amount);

        _sendSnapshotsToParentPool();
        _triggerDepositWithdrawProcess();
    }

    function withdraw(uint256 amount) external {
        uint256 lpBalance = i_lp.balanceOf(s_liquidityProvider);
        uint256 minWithdrawalAmount = i_parentPool.getMinWithdrawalAmount();

        if (lpBalance < minWithdrawalAmount) return;
        amount = bound(amount, minWithdrawalAmount, lpBalance);

        vm.prank(s_liquidityProvider);
        i_parentPool.enterWithdrawalQueue(amount);

        _sendSnapshotsToParentPool();
        _triggerDepositWithdrawProcess();

        if (i_parentPool.isReadyToProcessPendingWithdrawals()) {
            _processPendingWithdrawals();
        }
    }

    function bridge(uint256 srcActorIndexSeed, uint256 dstActorIndexSeed, uint256 amount) external {
        address srcPool = s_pools[bound(srcActorIndexSeed, 0, s_pools.length - 1)];
        address dstPool = s_pools[bound(dstActorIndexSeed, 0, s_pools.length - 1)];

        if (srcPool == dstPool) return;

        uint256 dstActiveBalance = Base(payable(dstPool)).getActiveBalance().toDecimals(
            s_usdcTokensByPool[dstPool].decimals,
            s_usdcTokensByPool[srcPool].decimals
        );
        if (dstActiveBalance == 0) return;

        amount = bound(amount, 0, dstActiveBalance);
        uint256 userBalance = s_usdcTokensByPool[srcPool].token.balanceOf(s_user);
        if (amount > userBalance) {
            amount = userBalance;
        }

        s_lpFeeAccByPool[srcPool] += Base(payable(srcPool)).getLpFee(amount);

        _bridge(srcPool, dstPool, amount);
    }

    function bridgeIOU(uint256 srcActorIndexSeed, uint256 dstActorIndexSeed) external {
        _takeLocalSurpluses();

        address srcPool = s_pools[bound(srcActorIndexSeed, 0, s_pools.length - 1)];
        address dstPool = s_pools[bound(dstActorIndexSeed, 0, s_pools.length - 1)];

        if (srcPool == dstPool) return;

        uint256 srcIOUBalance = s_iouTokensByPool[srcPool].token.balanceOf(s_rebalancer);
        uint256 dstIOUBalance = s_iouTokensByPool[dstPool].token.balanceOf(s_rebalancer).toDecimals(
            s_iouTokensByPool[dstPool].decimals,
            s_iouTokensByPool[srcPool].decimals
        );

        uint256 srcSurplus = Base(payable(srcPool)).getSurplus();
        uint256 dstSurplus = Base(payable(dstPool)).getSurplus().toDecimals(
            s_iouTokensByPool[dstPool].decimals,
            s_iouTokensByPool[srcPool].decimals
        );

        uint256 localSurplus;
        uint256 localIOUBalance;
        if (dstSurplus >= srcIOUBalance && srcIOUBalance > 0) {
            _bridgeIOU(srcPool, dstPool); // bridge srcIOUBalance to DST pool

            localSurplus = Base(payable(dstPool)).getSurplus();
            localIOUBalance = s_iouTokensByPool[dstPool].token.balanceOf(s_rebalancer);
            _takeLocalSurplus(dstPool, localSurplus, localIOUBalance);
        } else if (srcSurplus >= dstIOUBalance && dstIOUBalance > 0) {
            _bridgeIOU(dstPool, srcPool); // bridge dstIOUBalance to SRC pool

            localSurplus = srcSurplus;
            localIOUBalance = srcIOUBalance;
            _takeLocalSurplus(srcPool, localSurplus, localIOUBalance);
        } else {
            return;
        }
    }

    function fillDeficits() external {
        vm.startPrank(s_rebalancer);

        uint256 parentPoolDeficit = i_parentPool.getDeficit();
        uint256 childPool1Deficit = i_childPool_1.getDeficit();
        uint256 childPool2Deficit = i_childPool_2.getDeficit();

        uint256 parentPoolUsdcBalance = i_usdc.balanceOf(s_rebalancer);
        uint256 childPool1UsdcBalance = i_usdcWithDec8ChildPool_1.balanceOf(s_rebalancer);
        uint256 childPool2UsdcBalance = i_usdcWithDec18ChildPool_2.balanceOf(s_rebalancer);

        parentPoolDeficit = parentPoolDeficit > parentPoolUsdcBalance
            ? parentPoolUsdcBalance
            : parentPoolDeficit;
        childPool1Deficit = childPool1Deficit > childPool1UsdcBalance
            ? childPool1UsdcBalance
            : childPool1Deficit;
        childPool2Deficit = childPool2Deficit > childPool2UsdcBalance
            ? childPool2UsdcBalance
            : childPool2Deficit;

        if (parentPoolDeficit > 0) {
            i_parentPool.fillDeficit(parentPoolDeficit);
        }

        if (childPool1Deficit > 0) {
            i_childPool_1.fillDeficit(childPool1Deficit);
        }

        if (childPool2Deficit > 0) {
            i_childPool_2.fillDeficit(childPool2Deficit);
        }

        vm.stopPrank();
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

    function _bridgeIOU(address srcPool, address dstPool) internal {
        uint256 amount = s_iouTokensByPool[srcPool].token.balanceOf(s_rebalancer);
        i_conceroRouter.setSrcChainSelector(s_dstPoolChainSelectors[srcPool]);

        vm.prank(s_rebalancer);
        Rebalancer(payable(srcPool)).bridgeIOU{value: BRIDGE_FEE}(
            BridgeCodec.toBytes32(s_rebalancer),
            s_dstPoolChainSelectors[dstPool],
            amount
        );
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
        i_childPool_1.sendSnapshotToParentPool{value: 0.01 ether}();
        i_conceroRouter.setSrcChainSelector(CHILD_POOL_CHAIN_SELECTOR_2);
        i_childPool_2.sendSnapshotToParentPool{value: 0.01 ether}();
        vm.stopPrank();
    }

    function _triggerDepositWithdrawProcess() internal {
        i_conceroRouter.setSrcChainSelector(PARENT_POOL_CHAIN_SELECTOR);

        vm.prank(s_lancaKeeper);
        i_parentPool.triggerDepositWithdrawProcess();

        _removeLpFeeAcc();
    }

    function _processPendingWithdrawals() internal {
        vm.prank(s_lancaKeeper);
        i_parentPool.processPendingWithdrawals();
    }

    function _removeLpFeeAcc() internal {
        s_lpFeeAccByPool[address(i_parentPool)] = 0;
        s_lpFeeAccByPool[address(i_childPool_1)] = 0;
        s_lpFeeAccByPool[address(i_childPool_2)] = 0;
    }

    function _getToken(IERC20 token) internal view returns (Token memory) {
        return Token({token: token, decimals: IERC20Metadata(address(token)).decimals()});
    }
}
