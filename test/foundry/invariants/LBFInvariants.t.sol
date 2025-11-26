// SPDX-License-Identifier: UNLICENSED
/* solhint-disable func-name-mixedcase */
pragma solidity 0.8.28;

import {MessageCodec} from "@concero/v2-contracts/contracts/common/libraries/MessageCodec.sol";
import {ConceroRouterMockWithCall} from "../mocks/ConceroRouterMockWithCall.sol";

import {Decimals} from "contracts/common/libraries/Decimals.sol";

import {InvariantTestBase} from "./InvariantTestBase.sol";
import {LBFHandler} from "./LBFHandler.sol";

import {console} from "forge-std/src/console.sol";

contract LBFInvariants is InvariantTestBase {
    using Decimals for uint256;

    LBFHandler public s_lbfHandler;

    function setUp() public override {
        super.setUp();

        s_lbfHandler = new LBFHandler(
            address(s_parentPool),
            address(s_childPool_1),
            address(s_childPool_2),
            address(s_conceroRouterMockWithCall),
            address(s_usdc),
            address(s_usdcWithDec8ChildPool_1),
            address(s_usdcWithDec18ChildPool_2),
            address(s_lpToken),
            address(s_iouToken),
            address(s_iouTokenChildPool_1),
            address(s_iouTokenChildPool_2)
        );

        bytes4[] memory selectors = new bytes4[](7);
        selectors[0] = LBFHandler.deposit.selector;
        selectors[1] = LBFHandler.withdraw.selector;
        selectors[2] = LBFHandler.bridgeIOU.selector;
        selectors[3] = LBFHandler.bridge.selector;
        selectors[4] = LBFHandler.bridge.selector;
        selectors[5] = LBFHandler.bridge.selector;
        selectors[6] = LBFHandler.fillDeficits.selector;

        targetContract(address(s_lbfHandler));
        targetSelector(FuzzSelector({addr: address(s_lbfHandler), selectors: selectors}));
    }

    function invariant_totalTargetBalanceAlwaysLessThanOrEqualToActiveBalance() public view {
        uint256 totalTargetBalance = s_parentPool.getTargetBalance() +
            s_childPool_1.getTargetBalance().toDecimals(USDC_DEC_8, USDC_DEC_6) +
            s_childPool_2.getTargetBalance().toDecimals(USDC_DEC_18, USDC_DEC_6);
        uint256 totalActiveBalance = s_parentPool.getActiveBalance() +
            s_childPool_1.getActiveBalance().toDecimals(USDC_DEC_8, USDC_DEC_6) +
            s_childPool_2.getActiveBalance().toDecimals(USDC_DEC_18, USDC_DEC_6);

        /**
         /** @dev we adjust the precision of activeBalance
         * because pools with higher decimals perform more accurate activeBalance calculations
         */
        totalActiveBalance += 10;

        assert(totalTargetBalance <= totalActiveBalance);
    }

    function invariant_totalSurplusAlwaysMoreThanOrEqualTotalDeficit() public view {
        uint256 totalSurplus = s_parentPool.getSurplus() +
            s_childPool_1.getSurplus().toDecimals(USDC_DEC_8, USDC_DEC_6) +
            s_childPool_2.getSurplus().toDecimals(USDC_DEC_18, USDC_DEC_6);

        uint256 totalDeficit = s_parentPool.getDeficit() +
            s_childPool_1.getDeficit().toDecimals(USDC_DEC_8, USDC_DEC_6) +
            s_childPool_2.getDeficit().toDecimals(USDC_DEC_18, USDC_DEC_6);

        uint256 iouTotal = s_iouToken.totalSupply() +
            s_iouTokenChildPool_1.totalSupply().toDecimals(USDC_DEC_8, USDC_DEC_6) +
            s_iouTokenChildPool_2.totalSupply().toDecimals(USDC_DEC_18, USDC_DEC_6);

        /** @dev lpFeeAcc description:
         * The invariant test always selects functions in a random order.
         * Therefore, if the targetBalance has not been updated in all pools (i.e., the last call was not triggerDepositWithdrawProcess),
         * then the LP fee is included in totalSurplus, as it is still combined with the overall liquidity.
         */
        uint256 lpFeeAcc = s_lbfHandler.s_lpFeeAccByPool(address(s_parentPool)) +
            s_lbfHandler.s_lpFeeAccByPool(address(s_childPool_1)).toDecimals(
                USDC_DEC_8,
                USDC_DEC_6
            ) +
            s_lbfHandler.s_lpFeeAccByPool(address(s_childPool_2)).toDecimals(
                USDC_DEC_18,
                USDC_DEC_6
            );

        totalSurplus = totalSurplus >= lpFeeAcc ? totalSurplus - lpFeeAcc : totalSurplus;
        totalDeficit = totalDeficit + iouTotal;

        assertApproxEqAbs(totalSurplus, totalDeficit, 100);
    }

    // TODO LP balance >= active balance
    // function invariant_lpBalanceAlwaysMoreThanOrEqualToActiveBalance() public view {
    //     uint256 lpBalance = s_lpToken.balanceOf(s_liquidityProvider);
    //     uint256 activeBalance = s_parentPool.getActiveBalance() +
    //         s_childPool_1.getActiveBalance() +
    //         s_childPool_2.getActiveBalance();

    //     console.log("lpBalance", lpBalance);
    //     console.log("activeBalance", activeBalance);

    //     uint256 lpRequired = lpBalance * activeBalance / s_lpToken.totalSupply();

    //     assert(lpRequired >= activeBalance);
    // }
}
