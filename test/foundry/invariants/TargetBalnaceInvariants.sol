// SPDX-License-Identifier: UNLICENSED
/* solhint-disable func-name-mixedcase */
pragma solidity 0.8.28;

import {Test} from "forge-std/src/Test.sol";

import {ChildPool} from "contracts/ChildPool/ChildPool.sol";
import {ParentPoolHarness} from "../harnesses/ParentPoolHarness.sol";
import {ConceroRouterMockWithCall} from "../mocks/ConceroRouterMockWithCall.sol";
import {Base} from "contracts/Base/Base.sol";

import {LancaBridgeBase} from "../LancaBridge/LancaBridgeBase.sol";

contract TargetBalanceHandler is Test {
    ParentPoolHarness internal immutable i_parentPool;
    ChildPool internal immutable i_childPool_1;
    ChildPool internal immutable i_childPool_2;
    ConceroRouterMockWithCall internal immutable i_conceroRouter;

    address[] pools;

    constructor(
        address parentPool,
        address childPool1,
        address childPool2,
        address conceroRouter,
        address usdc,
        address lp,
        address iou
    ) {
        i_parentPool = ParentPoolHarness(parentPool);
        i_childPool_1 = ChildPool(childPool1);
        i_childPool_2 = ChildPool(childPool2);

        pools.push(address(i_parentPool));
        pools.push(address(i_childPool_1));
        pools.push(address(i_childPool_2));

        i_conceroRouter = ConceroRouterMockWithCall(conceroRouter);
    }

    function deposit(uint256 amount) external {
        amount = bound(amount, i_parentPool.getMinDepositAmount(), usdc.balanceOf(user));

        _etherDepositQueue(amount);
        _sendSnapshotToParentPool();
        _triggerDepositWithdrawProcess();
    }

    function withdraw(uint256 amount) external {
        amount = bound(amount, 1e6, lp.balanceOf(user));

        _enterWithdrawalQueue(amount);

        _sendSnapshotToParentPool();
        _triggerDepositWithdrawProcess();
        _processPendingWithdrawals();
    }

    // TODO: we need to call this function more often then deposit and withdraw
    function bridge(uint256 srcActorIndexSeed, uint256 dstActorIndexSeed, uint256 amount) external {
        address srcPool = pools[bound(srcActorIndexSeed, 0, pools.length - 1)];
        address dstPool = pools[bound(dstActorIndexSeed, 0, pools.length - 1)];

        if (srcPool == dstPool) return;

        amount = bound(amount, 0, Base(dstPool).getActiveBalance());

        if (srcPool == address(i_parentPool)) {
            i_parentPool.bridge(dstPool, amount);
        } else if (srcPool == address(i_childPool1)) {
            i_childPool_1.bridge(dstPool, amount);
            i_conceroRouter.setSrcChainSelector(100);
        } else {
            i_childPool_2.bridge(dstPool, amount);
            i_conceroRouter.setSrcChainSelector(200);
        }

        _fillDeficits();
        _takeSurpluses();
    }

    function _etherDepositQueue(uint256 amount) internal {
        i_parentPool.enterDepositQueue(amount);
    }
    function _enterWithdrawalQueue(uint256 amount) internal {
        i_parentPool.enterWithdrawalQueue(amount);
    }

    function _triggerDepositWithdrawProcess() internal {
        i_parentPool.triggerDepositWithdrawProcess();
    }

    function _processPendingWithdrawals() internal {
        i_parentPool.processPendingWithdrawals();
    }

    function _sendSnapshotsToParentPool() internal {
        i_childPool_1.sendSnapshotToParentPool();
        i_childPool_2.sendSnapshotToParentPool();
    }

    function _fillDeficits() internal {
        uint256 deficit = i_parentPool.getDeficit();
        if (deficit > 0) {
            i_parentPool.fillDeficit(deficit);
        }

        deficit = i_childPool_1.getDeficit();
        if (deficit > 0) {
            i_childPool_1.fillDeficit(deficit);
        }

        deficit = i_childPool_2.getDeficit();
        if (deficit > 0) {
            i_childPool_2.fillDeficit(deficit);
        }
    }

    function _takeSurpluses() internal {
        uint256 surplus = i_parentPool.getSurplus();
        if (surplus > 0) {
            i_parentPool.takeSurplus(surplus);
        }

        surplus = i_childPool_1.getSurplus();
        if (surplus > 0) {
            i_childPool_1.takeSurplus(surplus);
        }

        surplus = i_childPool_2.getSurplus();
        if (surplus > 0) {
            i_childPool_2.takeSurplus(surplus);
        }
    }
}

contract TargetBalanceInvariants is LancaBridgeBase {
    TargetBalanceHandler internal s_targetBalanceHandler;

    function setUp() public override {
        super.setUp();

        s_targetBalanceHandler = new TargetBalanceHandler();

        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = TargetBalanceHandler.deposit.selector;
        selectors[1] = TargetBalanceHandler.withdraw.selector;
        selectors[2] = TargetBalanceHandler.bridge.selector;

        targetContract(address(s_targetBalanceHandler));
        targetSelector(FuzzSelector({addr: address(s_targetBalanceHandler), selectors: selectors}));
    }

    function invariant_totalTargetBalanceAlwaysEqualsToActiveBalance() public view {}
}
