// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {IConceroRouter} from "@concero/v2-contracts/contracts/interfaces/IConceroRouter.sol";
import {MessageCodec} from "@concero/v2-contracts/contracts/common/libraries/MessageCodec.sol";

import {Storage as rs} from "../../Rebalancer/libraries/Storage.sol";
import {Storage as pbs} from "../../Base/libraries/Storage.sol";
import {IBase} from "../../Base/interfaces/IBase.sol";
import {BridgeCodec} from "../../common/libraries/BridgeCodec.sol";
import {Decimals} from "../../common/libraries/Decimals.sol";
import {ICommonErrors} from "../../common/interfaces/ICommonErrors.sol";
import {IParentPool} from "../interfaces/IParentPool.sol";
import {LPToken} from "../LPToken.sol";
import {Storage as s} from "./Storage.sol";

/// @title Parent Pool Library
/// @notice Library with core liquidity, queue and rebalancing logic for the parent pool.
/// @dev
/// - Intended to be used via `delegatecall` from the `ParentPool` implementation.
/// - All storage access is done through `Storage.sol` (s.ParentPool, rs.Rebalancer, pbs.Base).
/// - Contains queue management, total balance aggregation and target balance calculations.
library ParentPoolLib {
    using Decimals for uint256;
    using BridgeCodec for bytes32;
    using BridgeCodec for bytes;
    using SafeERC20 for IERC20;

    uint8 internal constant SCALE_TOKEN_DECIMALS = 24;
    uint8 internal constant MAX_QUEUE_LENGTH = 250;
    uint32 internal constant CHILD_POOL_SNAPSHOT_EXPIRATION_TIME = 5 minutes;
    uint32 internal constant UPDATE_TARGET_BALANCE_MESSAGE_GAS_LIMIT = 100_000;

    /// @notice Parameter bundle used for `triggerDepositWithdrawalProcess`.
    /// @dev
    /// - Packs static configuration + dynamic inputs needed for target balance calculation.
    struct TriggerProcessParams {
        /// @notice Current active balance of the parent pool (in local liquidity token decimals).
        uint256 activeBalance;
        /// @notice IOU token address.
        address iouToken;
        /// @notice LP token address.
        address lpToken;
        /// @notice Concero router address used for cross-chain messages.
        address conceroRouter;
        /// @notice Decimals of the liquidity token.
        uint8 liquidityTokenDecimals;
        /// @notice Chain selector of the parent pool.
        uint24 parentChainSelector;
        /// @notice Sensitivity parameter for LUR score.
        uint256 lurScoreSensitivity;
        /// @notice Weight for LUR score in health calculation.
        uint256 lurScoreWeight;
        /// @notice Weight for NDR score in health calculation.
        uint256 ndrScoreWeight;
        /// @notice Scale factor for liquidity token (10 ** decimals).
        uint256 liquidityTokenScaleFactor;
        /// @notice Minimum allowed target balance for any pool.
        uint256 minTargetBalance;
        /// @notice Previous target balance of the parent pool.
        uint256 parentTargetBalance;
        /// @notice Previous day inflow/outflow for the parent pool.
        IBase.LiqTokenDailyFlow parentYesterdayFlow;
    }

    /// @notice Helper accumulator used in total pools balance calculation.
    struct TotalBalanceAccumulator {
        /// @notice Aggregate pools balance in scale decimals.
        uint256 totalPoolsBalance;
        /// @notice Total IOU sent (parent + children) in scale decimals.
        uint256 totalIouSent;
        /// @notice Total IOU received (parent + children) in scale decimals.
        uint256 totalIouReceived;
        /// @notice Aggregate IOU total supply (parent + children) in scale decimals.
        uint256 iouTotalSupply;
        /// @notice Total liquidity tokens sent (parent + children) in scale decimals.
        uint256 totalLiqTokenSent;
        /// @notice Total liquidity tokens received (parent + children) in scale decimals.
        uint256 totalLiqTokenReceived;
    }

    /// @notice Enqueues a user deposit into the parent pool deposit queue.
    /// @dev
    /// Requirements:
    /// - `minDepositAmount` must be set (`> 0`), otherwise reverts with `MinDepositAmountNotSet`.
    /// - `liquidityTokenAmount >= minDepositAmount`, otherwise reverts with `DepositAmountIsTooLow`.
    /// - `depositQueueIds.length < MAX_QUEUE_LENGTH`, otherwise reverts with `DepositQueueIsFull`.
    /// - `Total liquidity in the pool + deposit <= liquidityCap`, otherwise reverts with `LiquidityCapReached`.
    ///
    /// Effects:
    /// - Transfers `liquidityTokenAmount` of `liquidityToken` from `msg.sender` to the parent pool.
    /// - Creates a `Deposit` struct and stores it in `depositQueue` keyed by `depositId`.
    /// - Pushes `depositId` into `depositQueueIds`.
    /// - Increments `totalDepositAmountInQueue`.
    ///
    /// Emits:
    /// - `DepositQueued(depositId, lp, liquidityTokenAmount)`.
    ///
    /// @param s_parentPool Storage reference to parent pool state.
    /// @param liquidityTokenAmount Amount of liquidity token to deposit.
    /// @param liquidityToken Address of the liquidity token.
    function enterDepositQueue(
        s.ParentPool storage s_parentPool,
        uint256 liquidityTokenAmount,
        address liquidityToken
    ) external {
        uint256 minDepositAmount = s_parentPool.minDepositAmount;
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
            s_parentPool.prevTotalPoolsBalance +
                s_parentPool.totalDepositAmountInQueue +
                liquidityTokenAmount <=
                s_parentPool.liquidityCap,
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

    /// @notice Enqueues a user withdrawal into the parent pool withdrawal queue.
    /// @dev
    /// Requirements:
    /// - `minWithdrawalAmount` must be set (`> 0`), otherwise reverts with `MinWithdrawalAmountNotSet`.
    /// - `lpTokenAmount >= minWithdrawalAmount`, otherwise reverts with `WithdrawalAmountIsTooLow`.
    /// - `withdrawalQueueIds.length < MAX_QUEUE_LENGTH`, otherwise reverts with `WithdrawalQueueIsFull`.
    ///
    /// Effects:
    /// - Transfers `lpTokenAmount` of LP tokens from `msg.sender` to the parent pool.
    /// - Creates a `Withdrawal` struct and stores it in `withdrawalQueue` keyed by `withdrawalId`.
    /// - Pushes `withdrawalId` into `withdrawalQueueIds`.
    ///
    /// Emits:
    /// - `WithdrawalQueued(withdrawalId, lp, lpTokenAmount)`.
    ///
    /// @param s_parentPool Storage reference to parent pool state.
    /// @param lpTokenAmount Amount of LP tokens to enqueue for withdrawal.
    /// @param lpToken Address of the LP token.
    function enterWithdrawalQueue(
        s.ParentPool storage s_parentPool,
        uint256 lpTokenAmount,
        address lpToken
    ) external {
        uint256 minWithdrawalAmount = s_parentPool.minWithdrawalAmount;
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

    /// @notice Processes deposit and withdrawal queues and computes/propagates new target balances.
    /// @dev
    /// High-level steps:
    /// 1. Aggregates total pools balance across parent and children via `getTotalPoolsBalance`.
    ///    - Reverts with `ChildPoolSnapshotsAreNotReady` if any snapshot is stale or missing.
    /// 2. Updates `prevTotalPoolsBalance` with the new aggregate.
    /// 3. Processes full deposit queue via `_processDepositsQueue`:
    ///    - Mints LP tokens for each deposit.
    ///    - Applies rebalancer fee.
    /// 4. Processes full withdrawal queue via `_processWithdrawalsQueue`:
    ///    - Converts LP amounts to liquidity token amounts.
    ///    - Creates pending withdrawals.
    /// 5. Computes new target balances for all pools via `_calculateNewTargetBalances`.
    /// 6. Updates child targets and parent withdrawal locks via `_updateChildPoolTargetBalances`.
    ///
    /// Requirements:
    /// - All child snapshots must be within the valid timestamp range.
    ///
    /// @param s_parentPool Storage reference to parent pool state.
    /// @param s_rebalancer Storage reference to rebalancer state.
    /// @param s_base Storage reference to base state.
    /// @param params Struct with configuration and runtime parameters for the process.
    /// @param getActiveBalance Callback to fetch current active balance from ParentPool.
    /// @param getRebalancerFee Callback to compute rebalancer fee for a given amount.
    function triggerDepositWithdrawalProcess(
        s.ParentPool storage s_parentPool,
        rs.Rebalancer storage s_rebalancer,
        pbs.Base storage s_base,
        TriggerProcessParams calldata params,
        function() external returns (uint256) getActiveBalance,
        function(uint256) external view returns (uint256) getRebalancerFee
    ) external {
        uint256 totalPoolsBalance;
        {
            bool areChildPoolSnapshotsReady;
            (areChildPoolSnapshotsReady, totalPoolsBalance) = getTotalPoolsBalance(
                s_parentPool,
                s_rebalancer,
                s_base,
                params.activeBalance,
                IERC20(params.iouToken).totalSupply(),
                params.liquidityTokenDecimals
            );
            require(areChildPoolSnapshotsReady, IParentPool.ChildPoolSnapshotsAreNotReady());
        }

        s_parentPool.prevTotalPoolsBalance = totalPoolsBalance;

        uint256 totalRequestedWithdrawals;
        uint256 availableBalance;
        {
            uint256 deposited = _processDepositsQueue(
                s_parentPool,
                s_rebalancer,
                totalPoolsBalance,
                params.lpToken,
                getRebalancerFee
            );

            uint256 newTotalBalance = totalPoolsBalance + deposited;
            uint256 withdrawals = _processWithdrawalsQueue(
                s_parentPool,
                newTotalBalance,
                params.lpToken
            );
            totalRequestedWithdrawals = s_parentPool.remainingWithdrawalAmount + withdrawals;
            availableBalance = newTotalBalance - totalRequestedWithdrawals;
        }

        uint24[] memory chainSelectors;
        uint256[] memory targetBalances;
        {
            (chainSelectors, targetBalances) = _calculateNewTargetBalances(
                s_parentPool,
                availableBalance,
                params
            );
        }

        _updateChildPoolTargetBalances(
            s_parentPool,
            s_base,
            chainSelectors,
            targetBalances,
            totalRequestedWithdrawals,
            getActiveBalance(),
            params.parentChainSelector,
            params.conceroRouter,
            params.liquidityTokenDecimals
        );
    }

    /// @notice Processes all pending withdrawals and attempts to pay out users.
    /// @dev
    /// For each pending withdrawal:
    /// - Computes `(conceroFee, rebalanceFee)` via `getWithdrawalFee`.
    /// - Calculates `amountToWithdrawWithFee = liqTokenAmountToWithdraw - (conceroFee + rebalanceFee)`.
    /// - Tries to transfer `amountToWithdrawWithFee` to user via `safeTransferWrapper`:
    ///   * On success:
    ///       - Burns user's LP tokens via `LPToken(lpToken).burn`.
    ///       - Adds `conceroFee` to `totalLancaFee`.
    ///       - Adds `rebalanceFee` to `totalRebalancingFeeAmount`.
    ///       - Emits `WithdrawalCompleted`.
    ///   * On failure:
    ///       - Returns LP tokens back to the user.
    ///       - Emits `WithdrawalFailed`.
    ///
    /// After the loop:
    /// - Clears `pendingWithdrawalIds`.
    /// - Increases `s_rebalancer.totalRebalancingFeeAmount` by aggregated `totalRebalancingFeeAmount`.
    /// - Decreases `s_parentPool.totalWithdrawalAmountLocked` by `totalLiquidityTokenAmountToWithdraw`.
    /// - Increases `s_base.totalLancaFeeInLiqToken` by `totalLancaFee`.
    ///
    /// @param s_parentPool Storage reference to parent pool state.
    /// @param s_rebalancer Storage reference to rebalancer state.
    /// @param s_base Storage reference to base state.
    /// @param liquidityToken Address of the liquidity token being withdrawn.
    /// @param lpToken Address of the LP token.
    /// @param safeTransferWrapper Callback that safely transfers tokens from parent pool to user.
    /// @param getWithdrawalFee Callback to compute `(conceroFee, rebalancerFee)` for a given amount.
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
            IParentPool.PendingWithdrawal memory pendingWithdrawal = s_parentPool
                .pendingWithdrawals[pendingWithdrawalIds[i]];
            delete s_parentPool.pendingWithdrawals[pendingWithdrawalIds[i]];

            (uint256 conceroFee, uint256 rebalanceFee) = getWithdrawalFee(
                pendingWithdrawal.liqTokenAmountToWithdraw
            );
            uint256 amountToWithdrawWithFee = pendingWithdrawal.liqTokenAmountToWithdraw -
                (conceroFee + rebalanceFee);

            totalLiquidityTokenAmountToWithdraw += pendingWithdrawal.liqTokenAmountToWithdraw;

            try safeTransferWrapper(liquidityToken, pendingWithdrawal.lp, amountToWithdrawWithFee) {
                LPToken(lpToken).burn(pendingWithdrawal.lpTokenAmountToWithdraw);
                totalLancaFee += conceroFee;
                totalRebalancingFeeAmount += rebalanceFee;

                emit IParentPool.WithdrawalCompleted(
                    pendingWithdrawalIds[i],
                    amountToWithdrawWithFee
                );
            } catch {
                IERC20(lpToken).safeTransfer(
                    pendingWithdrawal.lp,
                    pendingWithdrawal.lpTokenAmountToWithdraw
                );

                emit IParentPool.WithdrawalFailed(
                    pendingWithdrawal.lp,
                    pendingWithdrawal.lpTokenAmountToWithdraw
                );

                continue;
            }
        }

        /* @dev do not clear this array before a loop because
                clearing it will affect getWithdrawalFee() */
        delete s_parentPool.pendingWithdrawalIds;

        s_rebalancer.totalRebalancingFeeAmount += totalRebalancingFeeAmount;
        s_parentPool.totalWithdrawalAmountLocked -= totalLiquidityTokenAmountToWithdraw;
        s_base.totalLancaFeeInLiqToken += totalLancaFee;
    }

    /// @notice Aggregates total effective pools balance from parent + child snapshots.
    /// @dev
    /// Steps:
    /// 1. Converts local (parent) stats to `SCALE_TOKEN_DECIMALS`:
    ///    - `activeBalance`,
    ///    - `totalIouSent`, `totalIouReceived`,
    ///    - `iouTotalSupply`,
    ///    - `totalLiqTokenSent`, `totalLiqTokenReceived`.
    /// 2. Iterates over all `supportedChainSelectors`:
    ///    - Verifies snapshot timestamp with `_isChildPoolSnapshotTimestampInRange`.
    ///    - Aggregates child balances and IOU/liquidity flows into the accumulator.
    /// 3. Computes:
    ///    - `iouOnTheWay = totalIouSent - totalIouReceived`,
    ///    - `liqTokenOnTheWay = totalLiqTokenSent - totalLiqTokenReceived`,
    ///    - `totalPoolsBalance = totalPoolsBalance - (liqTokenOnTheWay + iouTotalSupply + iouOnTheWay)`.
    /// 4. Converts `totalPoolsBalance` back to local `liquidityTokenDecimals`.
    ///
    /// Returns:
    /// - `(false, 0)` if some child snapshot is stale or invalid.
    /// - `(true, totalPoolsBalance)` otherwise.
    ///
    /// NOTE: The following invariants are assumed:
    /// - `totalIouSent >= totalIouReceived`,
    /// - `totalLiqTokenSent >= totalLiqTokenReceived`,
    /// - `totalPoolsBalance >= liqTokenOnTheWay + iouTotalSupply + iouOnTheWay`.
    ///
    /// @param s_parentPool Storage reference to parent pool state.
    /// @param s_rebalancer Storage reference to rebalancer state.
    /// @param s_poolBase Storage reference to base state.
    /// @param activeBalance Current active balance in local decimals.
    /// @param iouTotalSupply Total IOU token supply in local decimals.
    /// @param liquidityTokenDecimals Decimals of liquidity token.
    /// @return success True if all snapshots are valid and fresh.
    /// @return totalPoolsBalance Aggregated effective balance in local decimals.
    function getTotalPoolsBalance(
        s.ParentPool storage s_parentPool,
        rs.Rebalancer storage s_rebalancer,
        pbs.Base storage s_poolBase,
        uint256 activeBalance,
        uint256 iouTotalSupply,
        uint8 liquidityTokenDecimals
    ) public view returns (bool, uint256) {
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

    /// @notice Computes how much liquidity can be withdrawn for a given LP amount.
    /// @dev
    /// - Formula: `withdrawable = totalPoolsBalance * lpTokenAmount / totalLpSupply`.
    /// @param totalPoolsBalance Aggregated pools balance used for calculation.
    /// @param lpTokenAmount LP amount being redeemed.
    /// @param lpToken LP token address.
    /// @return Withdrawable liquidity amount in token units.
    function calculateWithdrawableAmount(
        uint256 totalPoolsBalance,
        uint256 lpTokenAmount,
        address lpToken
    ) public view returns (uint256) {
        // @dev USDC_WITHDRAWABLE = POOL_BALANCE x (LP_INPUT_AMOUNT / TOTAL_LP)
        return (totalPoolsBalance * lpTokenAmount) / IERC20(lpToken).totalSupply();
    }

    /*   PRIVATE HELPERS   */

    /// @notice Processes all queued deposits and mints LP tokens.
    /// @param s_parentPool Storage reference to ParentPool.
    /// @param s_rebalancer Storage reference to Rebalancer.
    /// @param totalPoolsBalance Total pools balance.
    /// @param lpToken LP token address.
    /// @param getRebalancerFee Function to get the rebalancer fee.
    /// @return totalDepositedLiqTokenAmount Total deposited liquidity amount after rebalancer fees.
    function _processDepositsQueue(
        s.ParentPool storage s_parentPool,
        rs.Rebalancer storage s_rebalancer,
        uint256 totalPoolsBalance,
        address lpToken,
        function(uint256) external view returns (uint256) getRebalancerFee
    ) private returns (uint256 totalDepositedLiqTokenAmount) {
        uint256 totalPoolBalanceWithLockedWithdrawals = totalPoolsBalance +
            s_parentPool.totalWithdrawalAmountLocked;

        bytes32[] memory depositQueueIds = s_parentPool.depositQueueIds;
        uint256 totalDepositFee;

        for (uint256 i; i < depositQueueIds.length; ++i) {
            bytes32 depositId = depositQueueIds[i];
            IParentPool.Deposit memory deposit = s_parentPool.depositQueue[depositId];
            delete s_parentPool.depositQueue[depositId];

            uint256 depositFee = getRebalancerFee(deposit.liquidityTokenAmountToDeposit);
            uint256 amountToDepositWithFee = deposit.liquidityTokenAmountToDeposit - depositFee;
            totalDepositFee += depositFee;

            uint256 lpTokenAmountToMint = _calculateLpTokenAmountToMint(
                totalPoolBalanceWithLockedWithdrawals + totalDepositedLiqTokenAmount,
                amountToDepositWithFee,
                lpToken
            );

            s_parentPool.totalDepositAmountInQueue -= deposit.liquidityTokenAmountToDeposit;
            LPToken(lpToken).mint(deposit.lp, lpTokenAmountToMint);
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
    function _processWithdrawalsQueue(
        s.ParentPool storage s_parentPool,
        uint256 totalPoolsBalance,
        address lpToken
    ) private returns (uint256 totalLiqTokenAmountToWithdraw) {
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

    /// @notice Calculates new target balances for all pools.
    /// @param s_parentPool Storage reference to ParentPool.
    /// @param totalLbfBalance Total available balance.
    /// @param params Calculation parameters.
    /// @return chainSelectors Array of pool chain selectors.
    /// @return newTargetBalances Target balances for each chain selector.
    function _calculateNewTargetBalances(
        s.ParentPool storage s_parentPool,
        uint256 totalLbfBalance,
        TriggerProcessParams memory params
    ) private view returns (uint24[] memory, uint256[] memory) {
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
                    SCALE_TOKEN_DECIMALS,
                    params.liquidityTokenDecimals
                ),
                outflow: _toLocalDecimals(
                    s_parentPool.childPoolSnapshots[childPoolChainSelectors[i]].dailyFlow.outflow,
                    SCALE_TOKEN_DECIMALS,
                    params.liquidityTokenDecimals
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
    /// - Computes new target balances using `_calculateNewTargetBalances`.
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
    function _updateChildPoolTargetBalances(
        s.ParentPool storage s_parentPool,
        pbs.Base storage s_base,
        uint24[] memory chainSelectors,
        uint256[] memory targetBalances,
        uint256 totalRequested,
        uint256 activeBalance,
        uint24 parentChainSelector,
        address conceroRouter,
        uint8 liquidityTokenDecimals
    ) private {
        for (uint256 i; i < chainSelectors.length; ++i) {
            // @dev check if it is child pool chain selector
            if (chainSelectors[i] != parentChainSelector) {
                _updateChildPoolTargetBalance(
                    s_parentPool,
                    s_base,
                    chainSelectors[i],
                    targetBalances[i],
                    liquidityTokenDecimals,
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
        TriggerProcessParams memory params
    ) private pure returns (uint256) {
        if (prevTargetBalance < params.minTargetBalance) {
            return params.minTargetBalance;
        }
        return
            (prevTargetBalance *
                _calculateLiquidityHealthScore(dailyFlow, prevTargetBalance, params)) /
            params.liquidityTokenScaleFactor;
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
        TriggerProcessParams memory params
    ) private pure returns (uint256) {
        uint256 lurScore = _calculateLiquidityUtilisationRatioScore(
            dailyFlow.inflow,
            dailyFlow.outflow,
            targetBalance,
            params.liquidityTokenScaleFactor,
            params.lurScoreSensitivity
        );

        uint256 ndrScore = _calculateNetDrainRateScore(
            dailyFlow.inflow,
            dailyFlow.outflow,
            targetBalance,
            params.liquidityTokenScaleFactor
        );

        uint256 lhs = ((params.lurScoreWeight * lurScore) + (params.ndrScoreWeight * ndrScore)) /
            params.liquidityTokenScaleFactor;

        return params.liquidityTokenScaleFactor + (params.liquidityTokenScaleFactor - lhs);
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
        uint256 lurScoreSensitivity
    ) private pure returns (uint256) {
        if (targetBalance == 0) return scaleFactor;
        uint256 lur = ((inflow + outflow) * scaleFactor) / targetBalance;
        return scaleFactor - ((lur * scaleFactor) / (lurScoreSensitivity + lur));
    }

    /// @notice Computes the Net Drain Rate (NDR) score.
    /// @dev
    /// - If `inflow >= outflow` or `targetBalance == 0`, returns maximum score.
    /// - If `ndr >= scaleFactor`, returns 0.
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

        if (ndr >= scaleFactor) return 0;

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
        uint8 srcDecimals,
        uint8 liquidityTokenDecimals
    ) internal pure returns (uint256) {
        return amountInSrcDecimals.toDecimals(srcDecimals, liquidityTokenDecimals);
    }
}
