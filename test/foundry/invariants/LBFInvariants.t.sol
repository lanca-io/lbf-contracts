// SPDX-License-Identifier: UNLICENSED
/* solhint-disable func-name-mixedcase */
pragma solidity 0.8.28;

import {InvariantTestBase} from "./InvariantTestBase.sol";
import {LBFHandler} from "./LBFHandler.sol";

contract LBFInvariants is InvariantTestBase {
    LBFHandler public s_lbfHandler;

    function setUp() public override {
        super.setUp();

        s_lbfHandler = new LBFHandler(
            address(s_parentPool),
            address(s_childPool_1),
            address(s_childPool_2),
            address(s_conceroRouterMockWithCall),
            address(s_usdc),
            address(s_lpToken),
            address(s_iouToken),
            user,
            liquidityProvider,
            s_lancaKeeper,
            operator
        );

        bytes4[] memory selectors = new bytes4[](5);
        selectors[0] = LBFHandler.deposit.selector;
        selectors[1] = LBFHandler.withdraw.selector;
        selectors[2] = LBFHandler.bridge.selector;
        selectors[3] = LBFHandler.bridge.selector;
        selectors[4] = LBFHandler.bridge.selector;

        targetContract(address(s_lbfHandler));
        targetSelector(FuzzSelector({addr: address(s_lbfHandler), selectors: selectors}));
    }

    function invariant_totalTargetBalanceAlwaysLessThanOrEqualToActiveBalance() public view {
        uint256 totalTargetBalance = s_parentPool.getTargetBalance() +
            s_childPool_1.getTargetBalance() +
            s_childPool_2.getTargetBalance();
        uint256 totalActiveBalance = s_parentPool.getActiveBalance() +
            s_childPool_1.getActiveBalance() +
            s_childPool_2.getActiveBalance();

        assert(totalTargetBalance <= totalActiveBalance);
    }

    function invariant_totalSurplusAlwaysMoreThanOrEqualTotalDeficit() public view {
        uint256 totalSurplus = s_parentPool.getSurplus() +
            s_childPool_1.getSurplus() +
            s_childPool_2.getSurplus();

        uint256 totalDeficit = s_parentPool.getDeficit() +
            s_childPool_1.getDeficit() +
            s_childPool_2.getDeficit();

        assert(totalSurplus >= totalDeficit);
    }

    function invariant_liquidityProviderFinalBalanceIsMoreThanInitialBalance() public {
        uint256 withdrawalAmount = s_lpToken.balanceOf(liquidityProvider);
        s_lbfHandler.withdraw(withdrawalAmount);

        assertGt(s_lbfHandler.s_totalWithdrawals(), s_lbfHandler.s_totalDeposits());
    }
}
