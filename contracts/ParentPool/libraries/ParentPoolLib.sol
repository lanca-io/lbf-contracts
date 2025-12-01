// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {IConceroRouter} from "@concero/v2-contracts/contracts/interfaces/IConceroRouter.sol";
import {MessageCodec} from "@concero/v2-contracts/contracts/common/libraries/MessageCodec.sol";

import {Storage as rs} from "../../Rebalancer/libraries/Storage.sol";
import {Storage as pbs} from "../../Base/libraries/Storage.sol";
import {IBase} from "../../Base/interfaces/IBase.sol";
import {Decimals} from "../../common/libraries/Decimals.sol";
import {BridgeCodec} from "../../common/libraries/BridgeCodec.sol";
import {ICommonErrors} from "../../common/interfaces/ICommonErrors.sol";
import {IParentPool} from "../interfaces/IParentPool.sol";
import {LPToken} from "../LPToken.sol";
import {Storage as s} from "./Storage.sol";

library ParentPoolLib {
    using Decimals for uint256;
    using BridgeCodec for bytes32;
    using BridgeCodec for bytes;
    using SafeERC20 for IERC20;

    uint8 internal constant LIQUIDITY_TOKEN_DECIMALS = 6;
    uint8 internal constant SCALE_TOKEN_DECIMALS = 24;
    uint8 internal constant MAX_QUEUE_LENGTH = 250;
    uint32 internal constant CHILD_POOL_SNAPSHOT_EXPIRATION_TIME = 5 minutes;
    uint32 internal constant UPDATE_TARGET_BALANCE_MESSAGE_GAS_LIMIT = 100_000;

    struct TargetBalanceCalculationParams {
        uint256 scaleFactor;
        uint64 lurScoreSensitivity;
        uint64 lurScoreWeight;
        uint64 ndrScoreWeight;
        uint256 minTargetBalance;
        uint24 parentChainSelector;
        uint256 parentTargetBalance;
        IBase.LiqTokenDailyFlow parentYesterdayFlow;
    }

    struct TotalBalanceAccumulator {
        uint256 totalPoolsBalance;
        uint256 totalIouSent;
        uint256 totalIouReceived;
        uint256 iouTotalSupply;
        uint256 totalLiqTokenSent;
        uint256 totalLiqTokenReceived;
    }

    struct ProcessWithdrawalResult {
        uint256 liqTokenAmount;
        uint256 lancaFee;
        uint256 rebalanceFee;
    }

    struct ProcessDepositsParams {
        uint256 totalPoolsBalance;
        uint8 rebalancerFeeBps;
        uint24 bpsDenominator;
        address lpToken;
    }

    /// @notice Computes how much liquidity can be withdrawn for a given LP amount.
    /// @dev
    /// - Formula: `withdrawable = totalPoolsBalance * lpTokenAmount / totalLpSupply`.
    /// @param totalPoolsBalance Aggregated pools balance used for calculation.
    /// @param lpTokenAmount LP amount being redeemed.
    /// @return Withdrawable liquidity amount in token units.
    function calculateWithdrawableAmount(
        uint256 totalPoolsBalance,
        uint256 lpTokenAmount,
        address lpToken
    ) public view returns (uint256) {
        // @dev USDC_WITHDRAWABLE = POOL_BALANCE x (LP_INPUT_AMOUNT / TOTAL_LP)
        return (totalPoolsBalance * lpTokenAmount) / IERC20(lpToken).totalSupply();
    }

    /// @notice Calculates new target balances for all pools.
    /// @param s_parentPool Storage reference to ParentPool.
    /// @param totalLbfBalance Total available balance.
    /// @param params Calculation parameters.
    /// @return chainSelectors Array of pool chain selectors.
    /// @return newTargetBalances Target balances for each chain selector.
    function calculateNewTargetBalances(
        s.ParentPool storage s_parentPool,
        uint256 totalLbfBalance,
        TargetBalanceCalculationParams memory params
    ) external view returns (uint24[] memory, uint256[] memory) {
        uint24[] memory childPoolChainSelectors = s_parentPool.supportedChainSelectors;
        uint256 childCount = childPoolChainSelectors.length;

        uint24[] memory chainSelectors = new uint24[](childCount + 1);
        uint256[] memory weights = new uint256[](childCount + 1);
        uint256 totalWeight;

        // Process child pools
        for (uint256 i; i < childCount; ++i) {
            chainSelectors[i] = childPoolChainSelectors[i];

            uint256 targetBalance = s_parentPool.childPoolTargetBalances[
                childPoolChainSelectors[i]
            ];

            IBase.LiqTokenDailyFlow memory dailyFlow = IBase.LiqTokenDailyFlow({
                inflow: _toLocalDecimals(
                    s_parentPool.childPoolSnapshots[childPoolChainSelectors[i]].dailyFlow.inflow,
                    SCALE_TOKEN_DECIMALS
                ),
                outflow: _toLocalDecimals(
                    s_parentPool.childPoolSnapshots[childPoolChainSelectors[i]].dailyFlow.outflow,
                    SCALE_TOKEN_DECIMALS
                )
            });

            weights[i] = _calculatePoolWeight(targetBalance, dailyFlow, params);
            totalWeight += weights[i];
        }

        // Process parent pool
        chainSelectors[childCount] = params.parentChainSelector;
        weights[childCount] = _calculatePoolWeight(
            params.parentTargetBalance,
            params.parentYesterdayFlow,
            params
        );
        totalWeight += weights[childCount];

        // Calculate new target balances
        uint256[] memory newTargetBalances = new uint256[](childCount + 1);
        for (uint256 i; i < newTargetBalances.length; ++i) {
            newTargetBalances[i] = _calculateTargetBalance(
                weights[i],
                totalWeight,
                totalLbfBalance
            );
        }

        return (chainSelectors, newTargetBalances);
    }

    /// @notice Updates target balances for all pools and locks/allocates withdrawals.
    /// @dev
    /// - Computes new target balances using `ParentPoolLib::calculateNewTargetBalances`.
    /// - For each pool:
    ///   * If child pool:
    ///     - sends `UPDATE_TARGET_BALANCE` message via `_updateChildPoolTargetBalance`,
    ///     - clears snapshot timestamp to prevent reuse.
    ///   * If parent pool:
    ///     - updates:
    ///       - `totalWithdrawalAmountLocked`,
    ///       - `remainingWithdrawalAmount`,
    ///       - `targetBalanceFloor`,
    ///       - base `targetBalance`.
    function updateChildPoolTargetBalances(
        s.ParentPool storage s_parentPool,
        pbs.Base storage s_base,
        uint24[] memory chainSelectors,
        uint256[] memory targetBalances,
        uint256 totalRequested,
        uint256 activeBalance,
        uint24 parentChainSelector,
        address conceroRouter
    ) external {
        for (uint256 i; i < chainSelectors.length; ++i) {
            // @dev check if it is child pool chain selector
            if (chainSelectors[i] != parentChainSelector) {
                _updateChildPoolTargetBalance(
                    s_parentPool,
                    s_base,
                    chainSelectors[i],
                    targetBalances[i],
                    LIQUIDITY_TOKEN_DECIMALS,
                    conceroRouter
                );

                /* @dev we only delete the timestamp because
                        that is enough to prevent it from passing
                        _isChildPoolSnapshotTimestampInRange(snapshotTimestamp)
                        and being used a second time */
                delete s_parentPool.childPoolSnapshots[chainSelectors[i]].timestamp;
            } else {
                uint256 updatedSurplus = activeBalance > targetBalances[i]
                    ? activeBalance - targetBalances[i]
                    : 0;

                uint256 coveredBySurplus = updatedSurplus >= totalRequested
                    ? totalRequested
                    : updatedSurplus;

                uint256 remaining = totalRequested - coveredBySurplus;

                s_parentPool.totalWithdrawalAmountLocked += coveredBySurplus;
                s_parentPool.remainingWithdrawalAmount = remaining;
                s_parentPool.targetBalanceFloor = targetBalances[i];

                s_base.targetBalance = targetBalances[i] + remaining;
            }
        }
    }

    /// @notice Sends an `UPDATE_TARGET_BALANCE` message to a child pool if its target changes.
    /// @dev
    /// - Skips if `childPoolTargetBalances[dstChainSelector] == newTargetBalance`.
    /// - Validates that a child pool is configured for `dstChainSelector`.
    /// - Builds a Concero message with:
    ///   * destination = child pool,
    ///   * payload = encoded update target balance data.
    /// - Obtains message fee via `getMessageFee` and immediately sends via `conceroSend`.
    /// @param dstChainSelector Child pool chain selector.
    /// @param newTargetBalance New target balance in local liquidity token decimals.
    function _updateChildPoolTargetBalance(
        s.ParentPool storage s_parentPool,
        pbs.Base storage s_base,
        uint24 dstChainSelector,
        uint256 newTargetBalance,
        uint8 liquidityTokenDecimals,
        address conceroRouter
    ) private {
        if (s_parentPool.childPoolTargetBalances[dstChainSelector] == newTargetBalance) return;
        s_parentPool.childPoolTargetBalances[dstChainSelector] = newTargetBalance;

        bytes32 childPool = s_base.dstPools[dstChainSelector];
        require(childPool != bytes32(0), ICommonErrors.InvalidDstChainSelector(dstChainSelector));

        address[] memory validatorLibs = new address[](1);
        validatorLibs[0] = s_base.validatorLib;

        IConceroRouter.MessageRequest memory messageRequest = IConceroRouter.MessageRequest({
            dstChainSelector: dstChainSelector,
            srcBlockConfirmations: 0,
            feeToken: address(0),
            dstChainData: MessageCodec.encodeEvmDstChainData(
                childPool.toAddress(),
                UPDATE_TARGET_BALANCE_MESSAGE_GAS_LIMIT
            ),
            validatorLibs: validatorLibs,
            relayerLib: s_base.relayerLib,
            validatorConfigs: new bytes[](1),
            relayerConfig: new bytes(0),
            payload: BridgeCodec.encodeUpdateTargetBalanceData(
                newTargetBalance,
                liquidityTokenDecimals
            )
        });

        uint256 messageFee = IConceroRouter(conceroRouter).getMessageFee(messageRequest);

        IConceroRouter(conceroRouter).conceroSend{value: messageFee}(messageRequest);
    }

    /// @notice Aggregates total pools balance from parent + child snapshots.
    /// @param s_parentPool Storage reference to ParentPool.
    /// @param s_rebalancer Storage reference to Rebalancer.
    /// @param s_poolBase Storage reference to Base.
    /// @param activeBalance Current active balance.
    /// @param iouTotalSupply Total IOU token supply.
    /// @param liquidityTokenDecimals Decimals of liquidity token.
    /// @return success True if all snapshots are valid and fresh.
    /// @return totalPoolsBalance Aggregated balance in local decimals.
    function getTotalPoolsBalance(
        s.ParentPool storage s_parentPool,
        rs.Rebalancer storage s_rebalancer,
        pbs.Base storage s_poolBase,
        uint256 activeBalance,
        uint256 iouTotalSupply,
        uint8 liquidityTokenDecimals
    ) external view returns (bool, uint256) {
        TotalBalanceAccumulator memory acc;
        acc.totalPoolsBalance = _toScaleDecimals(activeBalance, liquidityTokenDecimals);
        acc.totalIouSent = _toScaleDecimals(s_rebalancer.totalIouSent, liquidityTokenDecimals);
        acc.totalIouReceived = _toScaleDecimals(
            s_rebalancer.totalIouReceived,
            liquidityTokenDecimals
        );
        acc.iouTotalSupply = _toScaleDecimals(iouTotalSupply, liquidityTokenDecimals);
        acc.totalLiqTokenSent = _toScaleDecimals(
            s_poolBase.totalLiqTokenSent,
            liquidityTokenDecimals
        );
        acc.totalLiqTokenReceived = _toScaleDecimals(
            s_poolBase.totalLiqTokenReceived,
            liquidityTokenDecimals
        );

        uint24[] memory selectors = s_parentPool.supportedChainSelectors;
        for (uint256 i; i < selectors.length; ++i) {
            if (
                !_isChildPoolSnapshotTimestampInRange(
                    s_parentPool.childPoolSnapshots[selectors[i]].timestamp
                )
            ) {
                return (false, 0);
            }

            acc.totalPoolsBalance += s_parentPool.childPoolSnapshots[selectors[i]].balance;
            acc.totalIouSent += s_parentPool.childPoolSnapshots[selectors[i]].iouTotalSent;
            acc.totalIouReceived += s_parentPool.childPoolSnapshots[selectors[i]].iouTotalReceived;
            acc.iouTotalSupply += s_parentPool.childPoolSnapshots[selectors[i]].iouTotalSupply;
            acc.totalLiqTokenSent += s_parentPool
                .childPoolSnapshots[selectors[i]]
                .totalLiqTokenSent;
            acc.totalLiqTokenReceived += s_parentPool
                .childPoolSnapshots[selectors[i]]
                .totalLiqTokenReceived;
        }

        uint256 iouOnTheWay = acc.totalIouSent - acc.totalIouReceived;
        uint256 liqTokenOnTheWay = acc.totalLiqTokenSent - acc.totalLiqTokenReceived;

        acc.totalPoolsBalance =
            acc.totalPoolsBalance - (liqTokenOnTheWay + acc.iouTotalSupply + iouOnTheWay);

        return (
            true,
            acc.totalPoolsBalance.toDecimals(SCALE_TOKEN_DECIMALS, liquidityTokenDecimals)
        );
    }

    function enterDepositQueue(
        s.ParentPool storage s_parentPool,
        uint256 liquidityTokenAmount,
        address liquidityToken
    ) external {
        uint64 minDepositAmount = s_parentPool.minDepositAmount;
        require(minDepositAmount > 0, ICommonErrors.MinDepositAmountNotSet());
        require(
            liquidityTokenAmount >= minDepositAmount,
            ICommonErrors.DepositAmountIsTooLow(liquidityTokenAmount, minDepositAmount)
        );

        require(
            s_parentPool.depositQueueIds.length < MAX_QUEUE_LENGTH,
            IParentPool.DepositQueueIsFull()
        );
        require(
            s_parentPool.prevTotalPoolsBalance <= s_parentPool.liquidityCap,
            IParentPool.LiquidityCapReached(s_parentPool.liquidityCap)
        );

        IERC20(liquidityToken).safeTransferFrom(msg.sender, address(this), liquidityTokenAmount);

        IParentPool.Deposit memory deposit = IParentPool.Deposit({
            liquidityTokenAmountToDeposit: liquidityTokenAmount,
            lp: msg.sender
        });
        bytes32 depositId = keccak256(
            abi.encodePacked(msg.sender, block.number, ++s_parentPool.depositNonce)
        );

        s_parentPool.depositQueue[depositId] = deposit;
        s_parentPool.depositQueueIds.push(depositId);
        s_parentPool.totalDepositAmountInQueue += liquidityTokenAmount;

        emit IParentPool.DepositQueued(depositId, deposit.lp, liquidityTokenAmount);
    }

    function enterWithdrawalQueue(
        s.ParentPool storage s_parentPool,
        uint256 lpTokenAmount,
        address lpToken
    ) external {
        uint64 minWithdrawalAmount = s_parentPool.minWithdrawalAmount;
        require(minWithdrawalAmount > 0, ICommonErrors.MinWithdrawalAmountNotSet());
        require(
            lpTokenAmount >= minWithdrawalAmount,
            ICommonErrors.WithdrawalAmountIsTooLow(lpTokenAmount, minWithdrawalAmount)
        );

        require(
            s_parentPool.withdrawalQueueIds.length < MAX_QUEUE_LENGTH,
            IParentPool.WithdrawalQueueIsFull()
        );

        IERC20(lpToken).safeTransferFrom(msg.sender, address(this), lpTokenAmount);

        IParentPool.Withdrawal memory withdraw = IParentPool.Withdrawal({
            lpTokenAmountToWithdraw: lpTokenAmount,
            lp: msg.sender
        });
        bytes32 withdrawalId = keccak256(
            abi.encodePacked(msg.sender, block.number, ++s_parentPool.withdrawalNonce)
        );

        s_parentPool.withdrawalQueue[withdrawalId] = withdraw;
        s_parentPool.withdrawalQueueIds.push(withdrawalId);

        emit IParentPool.WithdrawalQueued(withdrawalId, withdraw.lp, lpTokenAmount);
    }

    /// @notice Processes all queued deposits and mints LP tokens.
    /// @param s_parentPool Storage reference to ParentPool.
    /// @param s_rebalancer Storage reference to Rebalancer.
    /// @param params Parameters for processing deposits.
    /// @return totalDepositedLiqTokenAmount Total deposited liquidity amount after rebalancer fees.
    function processDepositsQueue(
        s.ParentPool storage s_parentPool,
        rs.Rebalancer storage s_rebalancer,
        ProcessDepositsParams calldata params
    ) external returns (uint256 totalDepositedLiqTokenAmount) {
        uint256 totalPoolBalanceWithLockedWithdrawals = params.totalPoolsBalance +
            s_parentPool.totalWithdrawalAmountLocked;

        bytes32[] memory depositQueueIds = s_parentPool.depositQueueIds;
        uint256 totalDepositFee;

        for (uint256 i; i < depositQueueIds.length; ++i) {
            bytes32 depositId = depositQueueIds[i];
            IParentPool.Deposit memory deposit = s_parentPool.depositQueue[depositId];
            delete s_parentPool.depositQueue[depositId];

            uint256 depositFee = (deposit.liquidityTokenAmountToDeposit * params.rebalancerFeeBps) /
                params.bpsDenominator;
            uint256 amountToDepositWithFee = deposit.liquidityTokenAmountToDeposit - depositFee;
            totalDepositFee += depositFee;

            uint256 lpTokenAmountToMint = _calculateLpTokenAmountToMint(
                totalPoolBalanceWithLockedWithdrawals + totalDepositedLiqTokenAmount,
                amountToDepositWithFee,
                params.lpToken
            );

            s_parentPool.totalDepositAmountInQueue -= deposit.liquidityTokenAmountToDeposit;
            LPToken(params.lpToken).mint(deposit.lp, lpTokenAmountToMint);
            totalDepositedLiqTokenAmount += amountToDepositWithFee;

            emit IParentPool.DepositProcessed(
                depositId,
                deposit.lp,
                amountToDepositWithFee,
                lpTokenAmountToMint
            );
        }

        delete s_parentPool.depositQueueIds;
        s_rebalancer.totalRebalancingFeeAmount += totalDepositFee;
    }

    /// @notice Processes all queued withdrawals and creates pending withdrawals.
    /// @param s_parentPool Storage reference to ParentPool.
    /// @param totalPoolsBalance Total balance.
    /// @param lpToken LP token address.
    /// @return totalLiqTokenAmountToWithdraw Total liquidity to withdraw.
    function processWithdrawalsQueue(
        s.ParentPool storage s_parentPool,
        uint256 totalPoolsBalance,
        address lpToken
    ) external returns (uint256 totalLiqTokenAmountToWithdraw) {
        uint256 totalPoolBalanceWithLockedWithdrawals = totalPoolsBalance +
            s_parentPool.totalWithdrawalAmountLocked;
        bytes32[] memory withdrawalQueueIds = s_parentPool.withdrawalQueueIds;

        for (uint256 i; i < withdrawalQueueIds.length; ++i) {
            IParentPool.Withdrawal memory withdrawal = s_parentPool.withdrawalQueue[
                withdrawalQueueIds[i]
            ];
            delete s_parentPool.withdrawalQueue[withdrawalQueueIds[i]];

            uint256 liqTokenAmountToWithdraw = calculateWithdrawableAmount(
                totalPoolBalanceWithLockedWithdrawals,
                withdrawal.lpTokenAmountToWithdraw,
                lpToken
            );

            totalLiqTokenAmountToWithdraw += liqTokenAmountToWithdraw;

            s_parentPool.pendingWithdrawals[withdrawalQueueIds[i]] = IParentPool.PendingWithdrawal({
                liqTokenAmountToWithdraw: liqTokenAmountToWithdraw,
                lpTokenAmountToWithdraw: withdrawal.lpTokenAmountToWithdraw,
                lp: withdrawal.lp
            });
            s_parentPool.pendingWithdrawalIds.push(withdrawalQueueIds[i]);

            emit IParentPool.WithdrawalProcessed(
                withdrawalQueueIds[i],
                withdrawal.lp,
                withdrawal.lpTokenAmountToWithdraw,
                liqTokenAmountToWithdraw
            );
        }

        delete s_parentPool.withdrawalQueueIds;
    }

    function processPendingWithdrawals(
        s.ParentPool storage s_parentPool,
        rs.Rebalancer storage s_rebalancer,
        pbs.Base storage s_base,
        address liquidityToken,
        address lpToken,
        function(address, address, uint256) external safeTransferWrapper,
        function(uint256) external view returns (uint256, uint256) getWithdrawalFee
    ) external {
        bytes32[] memory pendingWithdrawalIds = s_parentPool.pendingWithdrawalIds;
        uint256 totalLiquidityTokenAmountToWithdraw;
        uint256 totalLancaFee;
        uint256 totalRebalancingFeeAmount;

        for (uint256 i; i < pendingWithdrawalIds.length; ++i) {
            ProcessWithdrawalResult memory result = _processOneWithdrawal(
                s_parentPool,
                pendingWithdrawalIds[i],
                liquidityToken,
                lpToken,
                safeTransferWrapper,
                getWithdrawalFee
            );
            totalLiquidityTokenAmountToWithdraw += result.liqTokenAmount;
            totalLancaFee += result.lancaFee;
            totalRebalancingFeeAmount += result.rebalanceFee;
        }

        /* @dev do not clear this array before a loop because
                clearing it will affect getWithdrawalFee() */
        delete s_parentPool.pendingWithdrawalIds;

        s_rebalancer.totalRebalancingFeeAmount += totalRebalancingFeeAmount;
        s_parentPool.totalWithdrawalAmountLocked -= totalLiquidityTokenAmountToWithdraw;
        s_base.totalLancaFeeInLiqToken += totalLancaFee;
    }

    // ============ PRIVATE HELPERS ============

    function _processOneWithdrawal(
        s.ParentPool storage s_parentPool,
        bytes32 withdrawalId,
        address liquidityToken,
        address lpToken,
        function(address, address, uint256) external safeTransferWrapper,
        function(uint256) external view returns (uint256, uint256) getWithdrawalFee
    ) private returns (ProcessWithdrawalResult memory result) {
        IParentPool.PendingWithdrawal memory pw = s_parentPool.pendingWithdrawals[withdrawalId];
        delete s_parentPool.pendingWithdrawals[withdrawalId];

        result.liqTokenAmount = pw.liqTokenAmountToWithdraw;

        (uint256 conceroFee, uint256 rebalanceFee) = getWithdrawalFee(pw.liqTokenAmountToWithdraw);
        uint256 amountToWithdrawWithFee = pw.liqTokenAmountToWithdraw - (conceroFee + rebalanceFee);
        result.rebalanceFee = rebalanceFee;

        try safeTransferWrapper(liquidityToken, pw.lp, amountToWithdrawWithFee) {
            LPToken(lpToken).burn(pw.lpTokenAmountToWithdraw);
            result.lancaFee = conceroFee;
            emit IParentPool.WithdrawalCompleted(withdrawalId, amountToWithdrawWithFee);
        } catch {
            IERC20(lpToken).safeTransfer(pw.lp, pw.lpTokenAmountToWithdraw);
            emit IParentPool.WithdrawalFailed(pw.lp, pw.lpTokenAmountToWithdraw);
        }
    }

    /// @notice Calculates the amount of LP tokens to mint for a given deposit.
    /// @dev
    /// - If total LP supply is zero, mints 1:1 relative to deposit.
    /// - Otherwise:
    ///   * `lpTokens = totalSupply * deposit / totalLbfActiveBalance`.
    /// @param totalLbfActiveBalance Total aggregate balance considered for LP pricing.
    /// @param liquidityTokenAmountToDeposit Deposit amount after any fees.
    /// @param lpToken LP token address.
    /// @return Amount of LP tokens to mint.
    function _calculateLpTokenAmountToMint(
        uint256 totalLbfActiveBalance,
        uint256 liquidityTokenAmountToDeposit,
        address lpToken
    ) private view returns (uint256) {
        uint256 lpTokenTotalSupply = IERC20(lpToken).totalSupply();

        if (lpTokenTotalSupply == 0) return liquidityTokenAmountToDeposit;

        return (lpTokenTotalSupply * liquidityTokenAmountToDeposit) / totalLbfActiveBalance;
    }

    /// @notice Computes a pool weight based on previous target and daily flow.
    /// @dev
    /// - If `prevTargetBalance < i_minTargetBalance`:
    ///   * returns `i_minTargetBalance`.
    /// - Otherwise:
    ///   * `weight = prevTargetBalance * healthScore / scale`.
    /// @param prevTargetBalance Previous target balance for the pool.
    /// @param dailyFlow Daily inflow/outflow struct.
    /// @return Weight used in target balance calculation.
    function _calculatePoolWeight(
        uint256 prevTargetBalance,
        IBase.LiqTokenDailyFlow memory dailyFlow,
        TargetBalanceCalculationParams memory params
    ) private pure returns (uint256) {
        if (prevTargetBalance < params.minTargetBalance) {
            return params.minTargetBalance;
        }
        return
            (prevTargetBalance *
                _calculateLiquidityHealthScore(dailyFlow, prevTargetBalance, params)) /
            params.scaleFactor;
    }

    /// @notice Computes the overall liquidity health score of a pool.
    /// @dev
    /// - Combines LUR and NDR scores using configured weights:
    ///   * `lhs = (lurWeight * lurScore + ndrWeight * ndrScore) / scale`,
    ///   * healthScore = `scale + (scale - lhs)` (higher is healthier).
    /// @param dailyFlow Daily inflow/outflow struct.
    /// @param targetBalance Pool target balance.
    /// @param params Calculation parameters.
    /// @return Liquidity health score.
    function _calculateLiquidityHealthScore(
        IBase.LiqTokenDailyFlow memory dailyFlow,
        uint256 targetBalance,
        TargetBalanceCalculationParams memory params
    ) private pure returns (uint256) {
        uint256 lurScore = _calculateLiquidityUtilisationRatioScore(
            dailyFlow.inflow,
            dailyFlow.outflow,
            targetBalance,
            params.scaleFactor,
            params.lurScoreSensitivity
        );

        uint256 ndrScore = _calculateNetDrainRateScore(
            dailyFlow.inflow,
            dailyFlow.outflow,
            targetBalance,
            params.scaleFactor
        );

        uint256 lhs = ((params.lurScoreWeight * lurScore) + (params.ndrScoreWeight * ndrScore)) /
            params.scaleFactor;

        return params.scaleFactor + (params.scaleFactor - lhs);
    }

    /// @notice Computes the Liquidity Utilisation Ratio (LUR) score.
    /// @dev
    /// - If `targetBalance == 0`, returns maximum score (`scaleFactor`).
    /// - Otherwise:
    ///   * `lur = (inflow + outflow) * scale / targetBalance`,
    ///   * score = `scale - (lur * scale / (lurScoreSensitivity + lur))`.
    /// @param inflow Daily inflow amount.
    /// @param outflow Daily outflow amount.
    /// @param targetBalance Pool target balance.
    /// @return LUR score in [0, scale].
    function _calculateLiquidityUtilisationRatioScore(
        uint256 inflow,
        uint256 outflow,
        uint256 targetBalance,
        uint256 scaleFactor,
        uint64 lurScoreSensitivity
    ) private pure returns (uint256) {
        if (targetBalance == 0) return scaleFactor;
        uint256 lur = ((inflow + outflow) * scaleFactor) / targetBalance;
        return scaleFactor - ((lur * scaleFactor) / (lurScoreSensitivity + lur));
    }

    /// @notice Computes the Net Drain Rate (NDR) score.
    /// @dev
    /// - If `inflow >= outflow` or `targetBalance == 0`, returns maximum score.
    /// - Otherwise:
    ///   * `ndr = (outflow - inflow) * scale / targetBalance`,
    ///   * score = `scale - ndr`.
    /// @param inflow Daily inflow amount.
    /// @param outflow Daily outflow amount.
    /// @param targetBalance Pool target balance.
    /// @return NDR score in [0, scale].
    function _calculateNetDrainRateScore(
        uint256 inflow,
        uint256 outflow,
        uint256 targetBalance,
        uint256 scaleFactor
    ) private pure returns (uint256) {
        if (inflow >= outflow || targetBalance == 0) return scaleFactor;
        uint256 ndr = ((outflow - inflow) * scaleFactor) / targetBalance;
        return scaleFactor - ndr;
    }

    /// @notice Calculates a target balance given weight, total weight and total balance.
    /// @param weight Pool-specific weight.
    /// @param totalWeight Sum of all pool weights.
    /// @param totalLbfBalance Total available Lanca balance.
    /// @return Target balance for the pool.
    function _calculateTargetBalance(
        uint256 weight,
        uint256 totalWeight,
        uint256 totalLbfBalance
    ) private pure returns (uint256) {
        return (weight * totalLbfBalance) / totalWeight;
    }

    /// @notice Checks whether a child pool snapshot timestamp is fresh and valid.
    /// @dev
    /// - Rejects:
    ///   * zero timestamps,
    ///   * timestamps in the future,
    ///   * timestamps older than `CHILD_POOL_SNAPSHOT_EXPIRATION_TIME`.
    /// @param timestamp Snapshot timestamp.
    /// @return True if timestamp is within valid range; otherwise false.
    function _isChildPoolSnapshotTimestampInRange(uint32 timestamp) private view returns (bool) {
        if ((timestamp == 0) || (timestamp > block.timestamp)) return false;
        return (block.timestamp - timestamp) <= CHILD_POOL_SNAPSHOT_EXPIRATION_TIME;
    }

    /// @notice Converts an amount from arbitrary decimals to the internal scale decimals.
    /// @dev Uses `Decimals.toDecimals` helper under the hood.
    /// @param amountInSrcDecimals Amount in source decimals.
    /// @param srcDecimals Source token decimals.
    /// @return Amount scaled to `SCALE_TOKEN_DECIMALS`.
    function _toScaleDecimals(
        uint256 amountInSrcDecimals,
        uint8 srcDecimals
    ) private pure returns (uint256) {
        return amountInSrcDecimals.toDecimals(srcDecimals, SCALE_TOKEN_DECIMALS);
    }

    /// @notice Converts an amount from a source token's decimals to the local liquidity token decimals.
    /// @dev Uses `Decimals.toDecimals` helper for safe scaling.
    /// @param amountInSrcDecimals Amount expressed in `srcDecimals` units.
    /// @param srcDecimals Decimals of the source token.
    /// @return Amount scaled to `i_liquidityTokenDecimals`.
    function _toLocalDecimals(
        uint256 amountInSrcDecimals,
        uint8 srcDecimals
    ) internal pure returns (uint256) {
        return amountInSrcDecimals.toDecimals(srcDecimals, LIQUIDITY_TOKEN_DECIMALS);
    }
}
