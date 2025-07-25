// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {IConceroRouter} from "concero-v2/contracts/interfaces/IConceroRouter.sol";
import {ConceroTypes} from "concero-v2/contracts/ConceroClient/ConceroTypes.sol";
import {ICommonErrors} from "../common/interfaces/ICommonErrors.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ILancaKeeper} from "./interfaces/ILancaKeeper.sol";
import {IParentPool} from "./interfaces/IParentPool.sol";
import {LPToken} from "./LPToken.sol";
import {PoolBase} from "../PoolBase/PoolBase.sol";
import {Storage as s} from "./libraries/Storage.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {LPToken} from "./LPToken.sol";
import {Rebalancer} from "../Rebalancer/Rebalancer.sol";

contract ParentPool is IParentPool, ILancaKeeper, Rebalancer {
    using s for s.ParentPool;
    using SafeERC20 for IERC20;

    error ChildPoolSnapshotsAreNotReady();

    uint32 internal constant UPDATE_TARGET_BALANCE_MESSAGE_GAS_LIMIT = 100_000;
    LPToken internal immutable i_lpToken;

    modifier onlyLancaKeeper() {
        require(
            msg.sender == s.parentPool().lancaKeeper,
            ICommonErrors.UnauthorizedCaller(msg.sender, s.parentPool().lancaKeeper)
        );

        _;
    }

    constructor(
        address liquidityToken,
        uint8 liquidityTokenDecimals,
        address lpToken,
        address conceroRouter,
        uint24 chainSelector,
        address iouToken
    ) Rebalancer(conceroRouter, iouToken, liquidityToken, liquidityTokenDecimals, chainSelector) {
        i_lpToken = LPToken(lpToken);
    }

    receive() external payable {}

    function enterDepositQueue(uint256 liquidityTokenAmount) external {
        require(liquidityTokenAmount > 0, ICommonErrors.AmountIsToLow());

        IERC20(i_liquidityToken).safeTransferFrom(msg.sender, address(this), liquidityTokenAmount);

        Deposit memory deposit = Deposit({
            liquidityTokenAmountToDeposit: liquidityTokenAmount,
            lp: msg.sender
        });
        bytes32 depositId = keccak256(
            abi.encodePacked(msg.sender, block.number, ++s.parentPool().depositNonce)
        );

        s.parentPool().depositsQueue[depositId] = deposit;
        s.parentPool().depositsQueueIds.push(depositId);
        s.parentPool().totalDepositAmountInQueue += liquidityTokenAmount;

        emit DepositQueued(depositId, deposit.lp, liquidityTokenAmount);
    }

    function enterWithdrawQueue(uint256 lpTokenAmount) external {
        require(lpTokenAmount > 0, ICommonErrors.AmountIsToLow());

        IERC20(i_lpToken).safeTransferFrom(msg.sender, address(this), lpTokenAmount);

        Withdrawal memory withdraw = Withdrawal({
            lpTokenAmountToWithdraw: lpTokenAmount,
            lp: msg.sender
        });
        bytes32 withdrawId = keccak256(
            abi.encodePacked(msg.sender, block.number, ++s.parentPool().withdrawalNonce)
        );

        s.parentPool().withdrawalsQueue[withdrawId] = withdraw;
        s.parentPool().withdrawalsQueueIds.push(withdrawId);

        emit WithdrawQueued(withdrawId, withdraw.lp, lpTokenAmount);
    }

    function isReadyToTriggerDepositWithdrawProcess() external view returns (bool) {
        (bool success, ) = getTotalChildPoolsActiveBalance();
        return success;
    }

    function isLiquiditySnapshotTimestampInRange(uint32 timestamp) public pure returns (bool) {
        // TODO: implement it
        return true;
    }

    function isReadyToProcessPendingWithdrawals() public view returns (bool) {
        return
            (s.parentPool().remainingLiquidityToCollectForWithdraw == 0) &&
            (s.parentPool().totalAmountToWithdrawLocked > 0);
    }

    function getActiveBalance() public view override returns (uint256) {
        return
            super.getActiveBalance() -
            s.parentPool().totalDepositAmountInQueue -
            s.parentPool().totalAmountToWithdrawLocked;
    }

    function triggerDepositWithdrawProcess() external payable onlyLancaKeeper {
        (bool success, uint256 totalChildPoolsActiveBalance) = getTotalChildPoolsActiveBalance();
        require(success, ChildPoolSnapshotsAreNotReady());

        uint256 totalDepositedLiqTokenAmount = _processDepositsQueue(totalChildPoolsActiveBalance);
        uint256 totalLiqTokenAmountToWithdraw = _processWithdrawalsQueue(
            totalChildPoolsActiveBalance
        );

        if (totalDepositedLiqTokenAmount >= totalLiqTokenAmountToWithdraw) {
            _updateTargetBalancesWithInflow(
                totalChildPoolsActiveBalance + getActiveBalance() - totalLiqTokenAmountToWithdraw,
                totalLiqTokenAmountToWithdraw
            );
        } else {
            _updateTargetBalancesWithOutflow(
                totalChildPoolsActiveBalance + getActiveBalance(),
                totalLiqTokenAmountToWithdraw - totalDepositedLiqTokenAmount
            );
        }
    }

    function processPendingWithdrawals() external onlyLancaKeeper {
        require(
            isReadyToProcessPendingWithdrawals(),
            PendingWithdrawalsAreNotReady(
                s.parentPool().remainingLiquidityToCollectForWithdraw,
                s.parentPool().totalAmountToWithdrawLocked
            )
        );

        bytes32[] memory pendingWithdrawalIds = s.parentPool().pendingWithdrawalIds;
        PendingWithdrawal memory pendingWithdrawal;
        uint256 totalLiquidityTokenAmountToWithdraw;

        for (uint256 i; i < pendingWithdrawalIds.length; ++i) {
            pendingWithdrawal = s.parentPool().pendingWithdrawals[pendingWithdrawalIds[i]];
            i_lpToken.burn(pendingWithdrawal.lpTokenAmountToWithdraw);
            IERC20(i_liquidityToken).safeTransfer(
                pendingWithdrawal.lp,
                pendingWithdrawal.liqTokenAmountToWithdraw
            );
            totalLiquidityTokenAmountToWithdraw += pendingWithdrawal.liqTokenAmountToWithdraw;
        }

        s.parentPool().totalAmountToWithdrawLocked -= totalLiquidityTokenAmountToWithdraw;
    }

    function getTotalChildPoolsActiveBalance() public view returns (bool, uint256) {
        uint24[] memory supportedChainSelectors = s.parentPool().supportedChainSelectors;
        uint256 totalChildPoolsBalance;

        for (uint256 i; i < supportedChainSelectors.length; ++i) {
            uint32 snapshotTimestamp = s
                .parentPool()
                .childPoolsSubmissions[supportedChainSelectors[i]]
                .timestamp;

            if (!isLiquiditySnapshotTimestampInRange(snapshotTimestamp)) return (false, 0);

            totalChildPoolsBalance += s
                .parentPool()
                .childPoolsSubmissions[supportedChainSelectors[i]]
                .balance;
        }

        return (true, totalChildPoolsBalance);
    }

    /*   INTERNAL FUNCTIONS   */

    function _processDepositsQueue(
        uint256 totalChildPoolsActiveBalance
    ) internal returns (uint256) {
        bytes32[] memory depositsQueueIds = s.parentPool().depositsQueueIds;
        uint256 totalDepositedLiqTokenAmount;

        for (uint256 i; i < depositsQueueIds.length; ++i) {
            Deposit memory deposit = s.parentPool().depositsQueue[depositsQueueIds[i]];

            delete s.parentPool().depositsQueue[depositsQueueIds[i]];

            uint256 lpTokenAmountToMint = _calculateLpTokenAmountToMint(
                totalChildPoolsActiveBalance + getActiveBalance(),
                deposit.liquidityTokenAmountToDeposit
            );

            // TODO: may be more gas-optimal if you subtract one time outside the cycle
            s.parentPool().totalDepositAmountInQueue -= deposit.liquidityTokenAmountToDeposit;
            LPToken(i_liquidityToken).mint(deposit.lp, lpTokenAmountToMint);
            totalDepositedLiqTokenAmount += deposit.liquidityTokenAmountToDeposit;
        }

        delete s.parentPool().depositsQueueIds;

        return totalDepositedLiqTokenAmount;
    }

    function _processWithdrawalsQueue(
        uint256 totalChildPoolsActiveBalance
    ) internal returns (uint256) {
        bytes32[] memory withdrawalsQueueIds = s.parentPool().withdrawalsQueueIds;
        uint256 totalLiqTokenAmountToWithdraw;
        uint256 liqTokenAmountToWithdraw;
        Withdrawal memory withdrawal;

        for (uint256 i; i < withdrawalsQueueIds.length; ++i) {
            withdrawal = s.parentPool().withdrawalsQueue[withdrawalsQueueIds[i]];

            delete s.parentPool().withdrawalsQueue[withdrawalsQueueIds[i]];

            liqTokenAmountToWithdraw = _calculateWithdrawableAmount(
                totalChildPoolsActiveBalance,
                withdrawal.lpTokenAmountToWithdraw
            );

            totalLiqTokenAmountToWithdraw += liqTokenAmountToWithdraw;

            s.parentPool().pendingWithdrawals[withdrawalsQueueIds[i]] = PendingWithdrawal({
                liqTokenAmountToWithdraw: liqTokenAmountToWithdraw,
                lpTokenAmountToWithdraw: withdrawal.lpTokenAmountToWithdraw,
                lp: withdrawal.lp
            });
            s.parentPool().pendingWithdrawalIds.push(withdrawalsQueueIds[i]);
        }

        delete s.parentPool().withdrawalsQueueIds;

        return totalLiqTokenAmountToWithdraw;
    }

    function _updateTargetBalancesWithInflow(
        uint256 totalLbfBalance,
        uint256 totalAmountToWithdraw
    ) internal {
        (
            uint24[] memory chainSelectors,
            uint256[] memory targetBalances
        ) = _calculateNewTargetBalances(totalLbfBalance);

        s.parentPool().totalAmountToWithdrawLocked += totalAmountToWithdraw;

        for (uint256 i; i < chainSelectors.length; ++i) {
            if (chainSelectors[i] != i_chainSelector) {
                _updateChildPoolTargetBalance(chainSelectors[i], targetBalances[i]);
            } else {
                _setTargetBalance(targetBalances[i]);
            }
        }
    }

    function _updateTargetBalancesWithOutflow(uint256 totalLbfBalance, uint256 outflow) internal {
        uint256 surplus = getSurplus();
        bool isSurplusCoversOutflow = surplus >= outflow;
        // TODO: withdrawAL
        uint256 remainingAmountToCollectForWithdraw;

        if (!isSurplusCoversOutflow) {
            remainingAmountToCollectForWithdraw = outflow - surplus;
        }

        (
            uint24[] memory chainSelectors,
            uint256[] memory targetBalances
        ) = _calculateNewTargetBalances(totalLbfBalance - remainingAmountToCollectForWithdraw);

        for (uint256 i; i < chainSelectors.length; ++i) {
            if (chainSelectors[i] != i_chainSelector) {
                _updateChildPoolTargetBalance(chainSelectors[i], targetBalances[i]);
            } else {
                if (!isSurplusCoversOutflow) {
                    s
                        .parentPool()
                        .remainingLiquidityToCollectForWithdraw += remainingAmountToCollectForWithdraw;
                } else {
                    s.parentPool().totalAmountToWithdrawLocked += outflow;
                }

                _setTargetBalance(targetBalances[i] + remainingAmountToCollectForWithdraw);
            }
        }
    }

    function _calculateLpTokenAmountToMint(
        uint256 totalLbfActiveBalance,
        uint256 liquidityTokenAmountToDeposit
    ) internal returns (uint256) {
        uint256 lpTokenTotalSupply = IERC20(i_lpToken).totalSupply();

        if (lpTokenTotalSupply == 0) {
            return toLpTokenDecimals(liquidityTokenAmountToDeposit);
        }

        uint256 totalLbfActiveBalanceConverted = toLpTokenDecimals(totalLbfActiveBalance);
        uint256 liquidityTokenAmountToDepositConverted = toLpTokenDecimals(
            liquidityTokenAmountToDeposit
        );

        return
            (lpTokenTotalSupply * liquidityTokenAmountToDepositConverted) /
            totalLbfActiveBalanceConverted;
    }

    function _calculateWithdrawableAmount(
        uint256 totalChildPoolsActiveBalance,
        uint256 lpTokenAmount
    ) internal returns (uint256) {
        uint256 totalCrossChainLiquidity = totalChildPoolsActiveBalance + getActiveBalance();

        // @dev USDC_WITHDRAWABLE = POOL_BALANCE x (LP_INPUT_AMOUNT / TOTAL_LP)
        return
            toLiqTokenDecimals(
                (toLpTokenDecimals(totalCrossChainLiquidity) * lpTokenAmount) /
                    i_lpToken.totalSupply()
            );
    }

    function _calculateNewTargetBalances(
        uint256 totalLbfBalance
    ) internal view returns (uint24[] memory, uint256[] memory) {
        uint24[] memory childPoolChainSelectors = getSupportedChainSelectors();
        uint24[] memory chainSelectors = new uint24[](childPoolChainSelectors.length + 1);
        uint256[] memory weights = new uint256[](chainSelectors.length);
        LiqTokenDailyFlow memory dailyFlow;
        uint256 tagetBalance;
        uint256 targetBalancesSum;
        uint256 totalWeight;

        chainSelectors[chainSelectors.length - 1] = i_chainSelector;

        for (uint256 i; i < childPoolChainSelectors.length; ++i) {
            chainSelectors[i] = childPoolChainSelectors[i];
            dailyFlow = s.parentPool().childPoolsSubmissions[childPoolChainSelectors[i]].dailyFlow;

            tagetBalance = s.parentPool().dstChainsTargetBalances[childPoolChainSelectors[i]];
            targetBalancesSum += tagetBalance;

            // TODO: double check what should we do if tagetBalance initially 0
            weights[i] = tagetBalance * _calculateLhsScore(dailyFlow, tagetBalance);
            totalWeight += weights[i];
        }

        weights[weights.length - 1] = _calculateParentPoolTargetBalanceWeight();
        totalWeight += weights[weights.length - 1];

        uint256[] memory newTargetBalances = new uint256[](chainSelectors.length);

        for (uint256 i; i < newTargetBalances.length; ++i) {
            newTargetBalances[i] = _calculateTargetBalance(
                weights[i],
                totalWeight,
                totalLbfBalance
            );
        }

        return (childPoolChainSelectors, newTargetBalances);
    }

    // TODO: rename
    function _calculateLurScore(
        uint256 inflow,
        uint256 outflow,
        uint256 tagetBalance
    ) internal view returns (uint8) {
        uint256 lur = (inflow + outflow) / tagetBalance;

        return uint8(1 - (lur / (s.parentPool().lhsCalculationFactors.lurScoreSensitivity + lur)));
    }

    // TODO: rename to net drain rate
    function _calculateNdrScore(
        uint256 inflow,
        uint256 outflow,
        uint256 tagetBalance
    ) internal pure returns (uint8) {
        if (inflow >= outflow || tagetBalance == 0) return 1;

        uint256 ndr = (outflow - inflow) / tagetBalance;
        return uint8(1 - ndr);
    }

    function _calculateLhsScore(
        LiqTokenDailyFlow memory dailyFlow,
        uint256 tagetBalance
    ) internal view returns (uint8) {
        uint8 lurScore = _calculateLurScore(dailyFlow.inflow, dailyFlow.outflow, tagetBalance);
        uint8 ndrScore = _calculateNdrScore(dailyFlow.inflow, dailyFlow.outflow, tagetBalance);

        uint8 lhs = (s.parentPool().lhsCalculationFactors.lurScoreWeight * lurScore) +
            (s.parentPool().lhsCalculationFactors.ndrScoreWeight * ndrScore);

        return 1 + (1 - lhs);
    }

    function _calculateTargetBalance(
        uint256 weight,
        uint256 totalWeight,
        uint256 totalLbfBalance
    ) internal pure returns (uint256) {
        return (weight / totalWeight) * totalLbfBalance;
    }

    function _calculateParentPoolTargetBalanceWeight() internal view returns (uint256) {
        uint256 targetBalance = getTargetBalance();
        return targetBalance * _calculateLhsScore(getYesterdayFlow(), targetBalance);
    }

    function _updateChildPoolTargetBalance(
        uint24 dstChainSelector,
        uint256 newTargetBalance
    ) internal {
        if (s.parentPool().dstChainsTargetBalances[dstChainSelector] == newTargetBalance) return;
        s.parentPool().dstChainsTargetBalances[dstChainSelector] = newTargetBalance;

        address childPool = s.parentPool().childPools[dstChainSelector];
        require(childPool != address(0), ICommonErrors.InvalidDstChainSelector(dstChainSelector));

        ConceroTypes.EvmDstChainData memory dstChainData = ConceroTypes.EvmDstChainData({
            gasLimit: UPDATE_TARGET_BALANCE_MESSAGE_GAS_LIMIT,
            receiver: childPool
        });

        uint256 messageFee = IConceroRouter(i_conceroRouter).getMessageFee(
            dstChainSelector,
            false,
            address(0),
            dstChainData
        );

        bytes memory messagePayload = abi.encode(
            ConceroMessageType.UPDATE_TARGET_BALANCE,
            newTargetBalance
        );

        IConceroRouter(i_conceroRouter).conceroSend{value: messageFee}(
            dstChainSelector,
            false,
            address(0),
            dstChainData,
            messagePayload
        );
    }

    // TODO: it has to be virtual function in rebalancer
    function _postInflowRebalance(uint256 inflowLiqTokenAmount) internal {
        uint256 remainingLiquidityToCollectForWithdraw = s
            .parentPool()
            .remainingLiquidityToCollectForWithdraw;

        if (remainingLiquidityToCollectForWithdraw == 0) return;

        // TODO: decrement parent pool target balance;
        if (remainingLiquidityToCollectForWithdraw < inflowLiqTokenAmount) {
            delete s.parentPool().remainingLiquidityToCollectForWithdraw;
            s.parentPool().totalAmountToWithdrawLocked += remainingLiquidityToCollectForWithdraw;
        } else {
            s.parentPool().remainingLiquidityToCollectForWithdraw -= inflowLiqTokenAmount;
            s.parentPool().totalAmountToWithdrawLocked += inflowLiqTokenAmount;
        }
    }
}
