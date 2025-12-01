// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {ICommonErrors} from "../common/interfaces/ICommonErrors.sol";
import {IConceroRouter} from "@concero/v2-contracts/contracts/interfaces/IConceroRouter.sol";
import {MessageCodec} from "@concero/v2-contracts/contracts/common/libraries/MessageCodec.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {ILancaKeeper} from "./interfaces/ILancaKeeper.sol";
import {IParentPool} from "./interfaces/IParentPool.sol";
import {LPToken} from "./LPToken.sol";
import {Base} from "../Base/Base.sol";
import {Rebalancer} from "../Rebalancer/Rebalancer.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Storage as pbs} from "../Base/libraries/Storage.sol";
import {Storage as rs} from "../Rebalancer/libraries/Storage.sol";
import {Storage as s} from "./libraries/Storage.sol";
import {LancaBridge} from "../LancaBridge/LancaBridge.sol";
import {BridgeCodec} from "../common/libraries/BridgeCodec.sol";
import {Decimals} from "../common/libraries/Decimals.sol";
import {IBase} from "../Base/interfaces/IBase.sol";

/// @title Lanca Parent Pool
/// @notice Main Lanca pool on the "parent" chain aggregating liquidity and coordinating child pools.
/// @dev
/// - Responsibilities:
///   * Manages LP deposit and withdrawal queues.
///   * Tracks and processes pending withdrawals with fee accounting.
///   * Aggregates liquidity & flow data from child pools via snapshots.
///   * Computes and pushes new target balances to child pools.
///   * Integrates with:
///     - `Rebalancer` for rebalancing and IOU accounting,
///     - `LancaBridge` / `Base` for cross-chain bridge and pool logic,
///     - `LPToken` as LP share token.
/// - Access control:
///   * `ADMIN` – configuration changes (queue lengths, caps, fee hints, weights).
///   * `LANCA_KEEPER` – operational actions (processing queues, pending withdrawals).
contract ParentPool is IParentPool, ILancaKeeper, Rebalancer, LancaBridge {
    using s for s.ParentPool;
    using rs for rs.Rebalancer;
    using pbs for pbs.Base;
    using SafeERC20 for IERC20;
    using BridgeCodec for bytes32;
    using BridgeCodec for bytes;
    using Decimals for uint256;

    uint32 internal constant UPDATE_TARGET_BALANCE_MESSAGE_GAS_LIMIT = 100_000;
    uint32 internal constant CHILD_POOL_SNAPSHOT_EXPIRATION_TIME = 5 minutes;
    uint8 internal constant MAX_QUEUE_LENGTH = 250;
    uint8 internal constant SCALE_TOKEN_DECIMALS = 24;

    LPToken internal immutable i_lpToken;
    /// @notice Scaling factor for the liquidity token (10 ** decimals).
    uint256 internal immutable i_liquidityTokenScaleFactor;
    uint256 internal immutable i_minTargetBalance;

    constructor(
        address liquidityToken,
        address lpToken,
        address iouToken,
        address conceroRouter,
        uint24 chainSelector,
        uint256 minTargetBalance
    ) Base(liquidityToken, conceroRouter, iouToken, chainSelector) {
        i_lpToken = LPToken(lpToken);

        uint8 liquidityTokenDecimals = IERC20Metadata(liquidityToken).decimals();
        require(i_lpToken.decimals() == liquidityTokenDecimals, InvalidLiqTokenDecimals());

        i_minTargetBalance = minTargetBalance;
        i_liquidityTokenScaleFactor = 10 ** liquidityTokenDecimals;
    }

    /// @notice Enqueues a user deposit into the deposit queue.
    /// @dev
    /// - Validations:
    ///   * `minDepositAmount` must be set and `liquidityTokenAmount >= minDepositAmount`.
    ///   * `depositQueueIds.length < MAX_QUEUE_LENGTH`.
    ///   * `prevTotalPoolsBalance <= liquidityCap`.
    /// - Effects:
    ///   * Transfers liquidity tokens from sender to this contract.
    ///   * Stores a `Deposit` entry keyed by a unique `depositId`.
    ///   * Pushes `depositId` into `depositQueueIds`.
    ///   * Increases `totalDepositAmountInQueue`.
    /// - Emits `DepositQueued`.
    /// @param liquidityTokenAmount Amount of liquidity tokens to deposit into the pool.
    function enterDepositQueue(uint256 liquidityTokenAmount) external {
        s.ParentPool storage s_parentPool = s.parentPool();

        uint64 minDepositAmount = s_parentPool.minDepositAmount;
        require(minDepositAmount > 0, ICommonErrors.MinDepositAmountNotSet());
        require(
            liquidityTokenAmount >= minDepositAmount,
            ICommonErrors.DepositAmountIsTooLow(liquidityTokenAmount, minDepositAmount)
        );

        require(s_parentPool.depositQueueIds.length < MAX_QUEUE_LENGTH, DepositQueueIsFull());
        require(
            s_parentPool.prevTotalPoolsBalance <= s_parentPool.liquidityCap,
            LiquidityCapReached(s_parentPool.liquidityCap)
        );

        IERC20(i_liquidityToken).safeTransferFrom(msg.sender, address(this), liquidityTokenAmount);

        Deposit memory deposit = Deposit({
            liquidityTokenAmountToDeposit: liquidityTokenAmount,
            lp: msg.sender
        });
        bytes32 depositId = keccak256(
            abi.encodePacked(msg.sender, block.number, ++s_parentPool.depositNonce)
        );

        s_parentPool.depositQueue[depositId] = deposit;
        s_parentPool.depositQueueIds.push(depositId);
        s_parentPool.totalDepositAmountInQueue += liquidityTokenAmount;

        emit DepositQueued(depositId, deposit.lp, liquidityTokenAmount);
    }

    /// @notice Enqueues a user withdrawal into the withdrawal queue.
    /// @dev
    /// - Validations:
    ///   * `minWithdrawalAmount` must be set and `lpTokenAmount >= minWithdrawalAmount`.
    ///   * `withdrawalQueueIds.length < MAX_QUEUE_LENGTH`.
    /// - Effects:
    ///   * Transfers LP tokens from sender to this contract.
    ///   * Stores a `Withdrawal` entry keyed by a unique `withdrawalId`.
    ///   * Pushes `withdrawalId` into `withdrawalQueueIds`.
    /// - Emits `WithdrawalQueued`.
    /// @param lpTokenAmount Amount of LP tokens the user wants to withdraw.
    function enterWithdrawalQueue(uint256 lpTokenAmount) external {
        s.ParentPool storage s_parentPool = s.parentPool();

        uint64 minWithdrawalAmount = s_parentPool.minWithdrawalAmount;
        require(minWithdrawalAmount > 0, ICommonErrors.MinWithdrawalAmountNotSet());
        require(
            lpTokenAmount >= minWithdrawalAmount,
            ICommonErrors.WithdrawalAmountIsTooLow(lpTokenAmount, minWithdrawalAmount)
        );

        require(s_parentPool.withdrawalQueueIds.length < MAX_QUEUE_LENGTH, WithdrawalQueueIsFull());

        IERC20(i_lpToken).safeTransferFrom(msg.sender, address(this), lpTokenAmount);

        Withdrawal memory withdraw = Withdrawal({
            lpTokenAmountToWithdraw: lpTokenAmount,
            lp: msg.sender
        });
        bytes32 withdrawalId = keccak256(
            abi.encodePacked(msg.sender, block.number, ++s_parentPool.withdrawalNonce)
        );

        s_parentPool.withdrawalQueue[withdrawalId] = withdraw;
        s_parentPool.withdrawalQueueIds.push(withdrawalId);

        emit WithdrawalQueued(withdrawalId, withdraw.lp, lpTokenAmount);
    }

    /// @inheritdoc ILancaKeeper
    /// @notice Processes deposit and withdrawal queues and rebalances pool targets.
    /// @dev
    /// - Only callable by `LANCA_KEEPER`.
    /// - Steps:
    ///   1. Ensures deposit and withdrawal queues meet minimum lengths (`areQueuesFull()`).
    ///   2. Aggregates total pools balance from parent + all child pools (`_getTotalPoolsBalance`).
    ///   3. Processes deposits queue via `_processDepositsQueue`.
    ///   4. Processes withdrawals queue via `_processWithdrawalsQueue`.
    ///   5. Updates target balances across pools and locks withdrawals via `_processPoolsUpdate`.
    function triggerDepositWithdrawProcess() external onlyRole(LANCA_KEEPER) {
        require(areQueuesFull(), QueuesAreNotFull());

        (bool areChildPoolSnapshotsReady, uint256 totalPoolsBalance) = _getTotalPoolsBalance();
        require(areChildPoolSnapshotsReady, ChildPoolSnapshotsAreNotReady());

        s.ParentPool storage s_parentPool = s.parentPool();

        s_parentPool.prevTotalPoolsBalance = totalPoolsBalance;

        uint256 deposited = _processDepositsQueue(totalPoolsBalance);
        uint256 newTotalBalance = totalPoolsBalance + deposited;
        uint256 withdrawals = _processWithdrawalsQueue(newTotalBalance);
        uint256 totalRequestedWithdrawals = s_parentPool.remainingWithdrawalAmount + withdrawals;

        _processPoolsUpdate(newTotalBalance, totalRequestedWithdrawals);
    }

    /// @notice Processes pending withdrawals after pools have been updated/rebalanced.
    /// @dev
    /// - Only callable by `LANCA_KEEPER`.
    /// - Requires `isReadyToProcessPendingWithdrawals()`:
    ///   * `remainingWithdrawalAmount == 0`,
    ///   * `totalWithdrawalAmountLocked > 0`.
    /// - For each pending withdrawal:
    ///   * Computes Concero + rebalancer fees via `getWithdrawalFee`.
    ///   * Attempts to transfer liquidity tokens to LP:
    ///     - On success:
    ///       - Burns LP tokens,
    ///       - Accumulates Lanca + rebalancing fees,
    ///       - Emits `WithdrawalCompleted`.
    ///     - On failure:
    ///       - Returns LP tokens back to user,
    ///       - Emits `WithdrawalFailed`.
    /// - Updates:
    ///   * `totalWithdrawalAmountLocked`,
    ///   * `totalRebalancingFeeAmount`,
    ///   * `totalLancaFeeInLiqToken`.
    function processPendingWithdrawals() external onlyRole(LANCA_KEEPER) {
        s.ParentPool storage s_parentPool = s.parentPool();
        require(
            isReadyToProcessPendingWithdrawals(),
            PendingWithdrawalsAreNotReady(
                s_parentPool.remainingWithdrawalAmount,
                s_parentPool.totalWithdrawalAmountLocked
            )
        );

        bytes32[] memory pendingWithdrawalIds = s_parentPool.pendingWithdrawalIds;
        uint256 totalLiquidityTokenAmountToWithdraw;
        uint256 totalLancaFee;
        uint256 totalRebalancingFeeAmount;

        for (uint256 i; i < pendingWithdrawalIds.length; ++i) {
            PendingWithdrawal memory pendingWithdrawal = s_parentPool.pendingWithdrawals[
                pendingWithdrawalIds[i]
            ];
            delete s_parentPool.pendingWithdrawals[pendingWithdrawalIds[i]];

            (uint256 conceroFee, uint256 rebalanceFee) = getWithdrawalFee(
                pendingWithdrawal.liqTokenAmountToWithdraw
            );
            uint256 amountToWithdrawWithFee = pendingWithdrawal.liqTokenAmountToWithdraw -
                (conceroFee + rebalanceFee);
            totalRebalancingFeeAmount += rebalanceFee;

            totalLiquidityTokenAmountToWithdraw += pendingWithdrawal.liqTokenAmountToWithdraw;

            try
                this.safeTransferWrapper(
                    i_liquidityToken,
                    pendingWithdrawal.lp,
                    amountToWithdrawWithFee
                )
            {
                i_lpToken.burn(pendingWithdrawal.lpTokenAmountToWithdraw);
                totalLancaFee += conceroFee;

                emit WithdrawalCompleted(pendingWithdrawalIds[i], amountToWithdrawWithFee);
            } catch {
                IERC20(i_lpToken).safeTransfer(
                    pendingWithdrawal.lp,
                    pendingWithdrawal.lpTokenAmountToWithdraw
                );

                emit WithdrawalFailed(
                    pendingWithdrawal.lp,
                    pendingWithdrawal.lpTokenAmountToWithdraw
                );

                continue;
            }
        }

        /* @dev do not clear this array before a loop because
                clearing it will affect getWithdrawalFee() */
        delete s_parentPool.pendingWithdrawalIds;

        rs.rebalancer().totalRebalancingFeeAmount += totalRebalancingFeeAmount;

        s_parentPool.totalWithdrawalAmountLocked -= totalLiquidityTokenAmountToWithdraw;
        pbs.base().totalLancaFeeInLiqToken += totalLancaFee;
    }

    /// @notice Internal-only wrapper for safe ERC20 transfer from this contract.
    /// @dev
    /// - Used to allow `try/catch` on transfers to users in `processPendingWithdrawals`.
    /// - Only callable by this contract itself.
    /// @param token ERC20 token address.
    /// @param to Recipient address.
    /// @param amount Amount to transfer.
    function safeTransferWrapper(address token, address to, uint256 amount) external {
        require(msg.sender == address(this), OnlySelf());
        IERC20(token).safeTransfer(to, amount);
    }

    /*   VIEW FUNCTIONS   */

    /// @notice Returns the withdrawal fee for a given liquidity token amount.
    /// @dev
    /// - Returns `(conceroFee, rebalancerFee)`:
    ///   * `rebalancerFee = getRebalancerFee(liqTokenAmount)`,
    ///   * `conceroFee`:
    ///     - if no pending withdrawals: 0,
    ///     - else: `averageConceroMessageFee * childPoolsCount * 4 / pendingWithdrawalCount`.
    /// - `* 4` factor accounts for:
    ///   * fee on deposit + fee on withdrawal,
    ///   * each operation involves two messages (child → parent, parent → child).
    /// @param liqTokenAmount Liquidity token amount for which to estimate fees.
    /// @return conceroFee Estimated Concero-related fee portion.
    /// @return rebalancerFee Rebalancer fee portion.
    function getWithdrawalFee(uint256 liqTokenAmount) public view returns (uint256, uint256) {
        s.ParentPool storage s_parentPool = s.parentPool();
        uint256 pendingWithdrawalCount = s_parentPool.pendingWithdrawalIds.length;

        if (pendingWithdrawalCount == 0) {
            return (0, getRebalancerFee(liqTokenAmount));
        }

        /* @dev We multiply this by 4 because we collect the fee from
                the user upon withdrawal for both deposits
                and withdrawals, and when depositing or withdrawing,
                messages are sent twice: first childPools ->
                parentPool, then parentPool -> childPools */
        uint256 conceroFee = (s_parentPool.averageConceroMessageFee *
            getChildPoolChainSelectors().length *
            4) / pendingWithdrawalCount;

        return (conceroFee, getRebalancerFee(liqTokenAmount));
    }

    function getChildPoolChainSelectors() public view returns (uint24[] memory) {
        return s.parentPool().supportedChainSelectors;
    }

    /// @notice Returns a scaled view of a stored child pool snapshot in local token decimals.
    /// @dev
    /// - Internally snapshots are stored using `SCALE_TOKEN_DECIMALS`.
    /// - This function converts all fields back to local liquidity token decimals.
    /// @param chainSelector Chain selector of the child pool.
    /// @return snapshot `ChildPoolSnapshot` structure rescaled to local decimals.
    function getChildPoolSnapshot(
        uint24 chainSelector
    ) external view returns (ChildPoolSnapshot memory) {
        ChildPoolSnapshot memory snapshot = s.parentPool().childPoolSnapshots[chainSelector];

        snapshot.balance = _toLocalDecimals(snapshot.balance, SCALE_TOKEN_DECIMALS);
        snapshot.dailyFlow.inflow = _toLocalDecimals(
            snapshot.dailyFlow.inflow,
            SCALE_TOKEN_DECIMALS
        );
        snapshot.dailyFlow.outflow = _toLocalDecimals(
            snapshot.dailyFlow.outflow,
            SCALE_TOKEN_DECIMALS
        );
        snapshot.iouTotalSent = _toLocalDecimals(snapshot.iouTotalSent, SCALE_TOKEN_DECIMALS);
        snapshot.iouTotalReceived = _toLocalDecimals(
            snapshot.iouTotalReceived,
            SCALE_TOKEN_DECIMALS
        );
        snapshot.iouTotalSupply = _toLocalDecimals(snapshot.iouTotalSupply, SCALE_TOKEN_DECIMALS);
        snapshot.totalLiqTokenSent = _toLocalDecimals(
            snapshot.totalLiqTokenSent,
            SCALE_TOKEN_DECIMALS
        );
        snapshot.totalLiqTokenReceived = _toLocalDecimals(
            snapshot.totalLiqTokenReceived,
            SCALE_TOKEN_DECIMALS
        );

        return snapshot;
    }

    /// @notice Indicates whether the parent pool is ready to process deposit/withdraw queues.
    /// @dev
    /// - Requires:
    ///   * valid and fresh child pool snapshots (`_getTotalPoolsBalance`),
    ///   * queues meeting minimum lengths (`areQueuesFull()`).
    /// @return True if queues are full and snapshots are ready; otherwise false.
    function isReadyToTriggerDepositWithdrawProcess() external view returns (bool) {
        (bool success, ) = _getTotalPoolsBalance();
        return success && areQueuesFull();
    }

    /// @notice Checks whether both deposit and withdrawal queues meet minimum length thresholds.
    /// @return True if both queues are above their configured minimums; otherwise false.
    function areQueuesFull() public view returns (bool) {
        s.ParentPool storage s_parentPool = s.parentPool();

        uint256 withdrawalLength = s_parentPool.withdrawalQueueIds.length;
        uint256 depositLength = s_parentPool.depositQueueIds.length;

        if ((depositLength == 0) && withdrawalLength == 0) return false;

        return
            withdrawalLength >= s_parentPool.minWithdrawalQueueLength &&
            depositLength >= s_parentPool.minDepositQueueLength;
    }

    /// @notice Returns whether pending withdrawals are ready to be processed.
    /// @dev
    /// - Conditions:
    ///   * `remainingWithdrawalAmount == 0`,
    ///   * `totalWithdrawalAmountLocked > 0`.
    /// @return True if all conditions are satisfied; otherwise false.
    function isReadyToProcessPendingWithdrawals() public view returns (bool) {
        s.ParentPool storage s_parentPool = s.parentPool();
        return
            (s_parentPool.remainingWithdrawalAmount == 0) &&
            (s_parentPool.totalWithdrawalAmountLocked > 0);
    }

    /// @inheritdoc Base
    /// @notice Returns the active liquidity balance of the parent pool.
    /// @dev
    /// - Extends `Base.getActiveBalance()` by subtracting:
    ///   * `totalDepositAmountInQueue`,
    ///   * `totalWithdrawalAmountLocked`.
    /// @return Active balance available for new operations.
    function getActiveBalance() public view override returns (uint256) {
        s.ParentPool storage s_parentPool = s.parentPool();
        return
            super.getActiveBalance() -
            s_parentPool.totalDepositAmountInQueue -
            s_parentPool.totalWithdrawalAmountLocked;
    }

    function getMinDepositQueueLength() external view returns (uint16) {
        return s.parentPool().minDepositQueueLength;
    }

    function getMinWithdrawalQueueLength() external view returns (uint16) {
        return s.parentPool().minWithdrawalQueueLength;
    }

    function getPendingWithdrawalIds() external view returns (bytes32[] memory) {
        return s.parentPool().pendingWithdrawalIds;
    }

    function getLurScoreSensitivity() external view returns (uint64) {
        return s.parentPool().lurScoreSensitivity;
    }

    function getScoresWeights()
        external
        view
        returns (uint64 lurScoreWeight, uint64 ndrScoreWeight)
    {
        return (s.parentPool().lurScoreWeight, s.parentPool().ndrScoreWeight);
    }

    function getLiquidityCap() external view returns (uint256) {
        return s.parentPool().liquidityCap;
    }

    function getMinDepositAmount() external view returns (uint64) {
        return s.parentPool().minDepositAmount;
    }

    function getMinWithdrawalAmount() external view returns (uint64) {
        return s.parentPool().minWithdrawalAmount;
    }

    function getWithdrawableAmount(
        uint256 totalPoolsBalance,
        uint256 lpTokenAmount
    ) public view returns (uint256) {
        return _calculateWithdrawableAmount(totalPoolsBalance, lpTokenAmount);
    }

    /*   ADMIN FUNCTIONS   */

    function setMinDepositQueueLength(uint16 length) external onlyRole(ADMIN) {
        s.parentPool().minDepositQueueLength = length;
    }

    function setMinWithdrawalQueueLength(uint16 length) external onlyRole(ADMIN) {
        s.parentPool().minWithdrawalQueueLength = length;
    }

    function setDstPool(uint24 chainSelector, bytes32 dstPool) public override onlyRole(ADMIN) {
        super.setDstPool(chainSelector, dstPool);

        s.ParentPool storage s_parentPool = s.parentPool();

        uint24[] memory supportedChainSelectors = s_parentPool.supportedChainSelectors;

        for (uint256 i; i < supportedChainSelectors.length; ++i) {
            require(
                supportedChainSelectors[i] != chainSelector,
                ICommonErrors.InvalidChainSelector()
            );
        }

        s_parentPool.supportedChainSelectors.push(chainSelector);
    }

    /// @notice Sets the LUR score sensitivity parameter.
    /// @dev
    /// - Must satisfy:
    ///   * `lurScoreSensitivity > i_liquidityTokenScaleFactor`,
    ///   * `lurScoreSensitivity < 10 * i_liquidityTokenScaleFactor`.
    /// @param lurScoreSensitivity New LUR sensitivity parameter.
    function setLurScoreSensitivity(uint64 lurScoreSensitivity) external onlyRole(ADMIN) {
        require(
            (lurScoreSensitivity > i_liquidityTokenScaleFactor) &&
                (lurScoreSensitivity < (10 * i_liquidityTokenScaleFactor)),
            InvalidLurScoreSensitivity()
        );
        s.parentPool().lurScoreSensitivity = lurScoreSensitivity;
    }

    /// @notice Sets the weights used for liquidity health scoring.
    /// @dev
    /// - Requires: `lurScoreWeight + ndrScoreWeight == i_liquidityTokenScaleFactor`.
    /// @param lurScoreWeight New weight for LUR score.
    /// @param ndrScoreWeight New weight for NDR score.
    function setScoresWeights(
        uint64 lurScoreWeight,
        uint64 ndrScoreWeight
    ) external onlyRole(ADMIN) {
        require(
            lurScoreWeight + ndrScoreWeight == i_liquidityTokenScaleFactor,
            InvalidScoreWeights()
        );

        s.ParentPool storage s_parentPool = s.parentPool();

        s_parentPool.lurScoreWeight = lurScoreWeight;
        s_parentPool.ndrScoreWeight = ndrScoreWeight;
    }

    /// @notice Sets the global liquidity cap for the parent pool.
    /// @param newLiqCap New liquidity cap value.
    function setLiquidityCap(uint256 newLiqCap) external onlyRole(ADMIN) {
        s.parentPool().liquidityCap = newLiqCap;
    }

    function setMinDepositAmount(uint64 newMinDepositAmount) external onlyRole(ADMIN) {
        s.parentPool().minDepositAmount = newMinDepositAmount;
    }

    function setMinWithdrawalAmount(uint64 newMinWithdrawalAmount) external onlyRole(ADMIN) {
        s.parentPool().minWithdrawalAmount = newMinWithdrawalAmount;
    }

    /// @notice Sets the average Concero message fee used for withdrawal fee estimation.
    /// @param averageConceroMessageFee New average Concero message fee.
    function setAverageConceroMessageFee(uint96 averageConceroMessageFee) external onlyRole(ADMIN) {
        s.parentPool().averageConceroMessageFee = averageConceroMessageFee;
    }

    /*   INTERNAL FUNCTIONS   */

    /// @notice Processes all queued deposits and mints LP tokens.
    /// @dev
    /// - For each deposit:
    ///   * charges rebalancer fee,
    ///   * calculates LP to mint based on pre/post-deposit total balance,
    ///   * mints LP to depositor,
    ///   * updates `totalDepositAmountInQueue`.
    /// - Updates total rebalancing fee and clears deposit queue.
    /// @param totalPoolsBalance Aggregated total pools balance (before deposits).
    /// @return Total deposited liquidity amount after rebalancer fees.
    function _processDepositsQueue(uint256 totalPoolsBalance) internal returns (uint256) {
        s.ParentPool storage s_parentPool = s.parentPool();
        uint256 totalPoolBalanceWithLockedWithdrawals = totalPoolsBalance +
            s_parentPool.totalWithdrawalAmountLocked;

        bytes32[] memory depositQueueIds = s_parentPool.depositQueueIds;
        uint256 totalDepositedLiqTokenAmount;
        uint256 totalDepositFee;

        for (uint256 i; i < depositQueueIds.length; ++i) {
            Deposit memory deposit = s_parentPool.depositQueue[depositQueueIds[i]];

            delete s_parentPool.depositQueue[depositQueueIds[i]];

            uint256 depositFee = getRebalancerFee(deposit.liquidityTokenAmountToDeposit);
            uint256 amountToDepositWithFee = deposit.liquidityTokenAmountToDeposit - depositFee;
            totalDepositFee += depositFee;

            uint256 lpTokenAmountToMint = _calculateLpTokenAmountToMint(
                totalPoolBalanceWithLockedWithdrawals + totalDepositedLiqTokenAmount,
                amountToDepositWithFee
            );

            s_parentPool.totalDepositAmountInQueue -= deposit.liquidityTokenAmountToDeposit;
            LPToken(i_lpToken).mint(deposit.lp, lpTokenAmountToMint);
            totalDepositedLiqTokenAmount += amountToDepositWithFee;

            emit DepositProcessed(
                depositQueueIds[i],
                deposit.lp,
                amountToDepositWithFee,
                lpTokenAmountToMint
            );
        }

        delete s_parentPool.depositQueueIds;
        rs.rebalancer().totalRebalancingFeeAmount += totalDepositFee;

        return totalDepositedLiqTokenAmount;
    }

    /// @notice Processes all queued withdrawals and creates pending withdrawals.
    /// @dev
    /// - For each withdrawal:
    ///   * calculates withdrawable liquidity via `_calculateWithdrawableAmount`,
    ///   * accumulates total liquidity to withdraw,
    ///   * stores `PendingWithdrawal`,
    ///   * pushes ID into `pendingWithdrawalIds`.
    /// - Clears `withdrawalQueueIds`.
    /// @param totalPoolsBalance Total pools balance *after* processing deposits.
    /// @return Total liquidity token amount to be withdrawn (before fees).
    function _processWithdrawalsQueue(uint256 totalPoolsBalance) internal returns (uint256) {
        s.ParentPool storage s_parentPool = s.parentPool();
        uint256 totalPoolBalanceWithLockedWithdrawals = totalPoolsBalance +
            s_parentPool.totalWithdrawalAmountLocked;

        bytes32[] memory withdrawalQueueIds = s_parentPool.withdrawalQueueIds;
        uint256 totalLiqTokenAmountToWithdraw;
        uint256 liqTokenAmountToWithdraw;
        Withdrawal memory withdrawal;

        for (uint256 i; i < withdrawalQueueIds.length; ++i) {
            withdrawal = s_parentPool.withdrawalQueue[withdrawalQueueIds[i]];

            delete s_parentPool.withdrawalQueue[withdrawalQueueIds[i]];

            liqTokenAmountToWithdraw = _calculateWithdrawableAmount(
                totalPoolBalanceWithLockedWithdrawals,
                withdrawal.lpTokenAmountToWithdraw
            );

            totalLiqTokenAmountToWithdraw += liqTokenAmountToWithdraw;

            s_parentPool.pendingWithdrawals[withdrawalQueueIds[i]] = PendingWithdrawal({
                liqTokenAmountToWithdraw: liqTokenAmountToWithdraw,
                lpTokenAmountToWithdraw: withdrawal.lpTokenAmountToWithdraw,
                lp: withdrawal.lp
            });
            s_parentPool.pendingWithdrawalIds.push(withdrawalQueueIds[i]);

            emit WithdrawalProcessed(
                withdrawalQueueIds[i],
                withdrawal.lp,
                withdrawal.lpTokenAmountToWithdraw,
                liqTokenAmountToWithdraw
            );
        }

        delete s_parentPool.withdrawalQueueIds;

        return totalLiqTokenAmountToWithdraw;
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
    /// @param totalLbfBalance Total Lanca balance after accounting for requested withdrawals.
    /// @param totalRequested Total requested withdrawal amount (pre-locking).
    function _processPoolsUpdate(uint256 totalLbfBalance, uint256 totalRequested) internal {
        s.ParentPool storage s_parentPool = s.parentPool();

        (
            uint24[] memory chainSelectors,
            uint256[] memory targetBalances
        ) = _calculateNewTargetBalances(totalLbfBalance - totalRequested);

        for (uint256 i; i < chainSelectors.length; ++i) {
            // @dev check if it is child pool chain selector
            if (chainSelectors[i] != i_chainSelector) {
                _updateChildPoolTargetBalance(chainSelectors[i], targetBalances[i]);

                /* @dev we only delete the timestamp because
                        that is enough to prevent it from passing
                        _isChildPoolSnapshotTimestampInRange(snapshotTimestamp)
                        and being used a second time */
                delete s_parentPool.childPoolSnapshots[chainSelectors[i]].timestamp;
            } else {
                uint256 activeBalance = getActiveBalance();
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

                pbs.base().targetBalance = targetBalances[i] + remaining;
            }
        }
    }

    /// @notice Calculates the amount of LP tokens to mint for a given deposit.
    /// @dev
    /// - If total LP supply is zero, mints 1:1 relative to deposit.
    /// - Otherwise:
    ///   * `lpTokens = totalSupply * deposit / totalLbfActiveBalance`.
    /// @param totalLbfActiveBalance Total aggregate balance considered for LP pricing.
    /// @param liquidityTokenAmountToDeposit Deposit amount after any fees.
    /// @return Amount of LP tokens to mint.
    function _calculateLpTokenAmountToMint(
        uint256 totalLbfActiveBalance,
        uint256 liquidityTokenAmountToDeposit
    ) internal view returns (uint256) {
        uint256 lpTokenTotalSupply = IERC20(i_lpToken).totalSupply();

        if (lpTokenTotalSupply == 0) return liquidityTokenAmountToDeposit;

        return (lpTokenTotalSupply * liquidityTokenAmountToDeposit) / totalLbfActiveBalance;
    }

    /// @notice Computes how much liquidity can be withdrawn for a given LP amount.
    /// @dev
    /// - Formula: `withdrawable = totalPoolsBalance * lpTokenAmount / totalLpSupply`.
    /// @param totalPoolsBalance Aggregated pools balance used for calculation.
    /// @param lpTokenAmount LP amount being redeemed.
    /// @return Withdrawable liquidity amount in token units.
    function _calculateWithdrawableAmount(
        uint256 totalPoolsBalance,
        uint256 lpTokenAmount
    ) internal view returns (uint256) {
        // @dev USDC_WITHDRAWABLE = POOL_BALANCE x (LP_INPUT_AMOUNT / TOTAL_LP)
        return (totalPoolsBalance * lpTokenAmount) / i_lpToken.totalSupply();
    }

    /// @notice Calculates new target balances for each pool based on liquidity health scoring.
    /// @dev
    /// - For each child pool:
    ///   * converts stored snapshot flows to local decimals,
    ///   * uses stored `childPoolTargetBalances` as previous target balance,
    ///   * computes weight via `_calculatePoolWeight`.
    /// - For parent pool:
    ///   * uses `getTargetBalance()` and `getYesterdayFlow()` to compute weight.
    /// - Finally:
    ///   * `newTargetBalance[i] = weight[i] * totalLbfBalance / totalWeight`.
    /// @param totalLbfBalance Total available balance (after applying requested withdrawals).
    /// @return chainSelectors Array of pool chain selectors (children + parent).
    /// @return newTargetBalances Target balances for each chain selector.
    function _calculateNewTargetBalances(
        uint256 totalLbfBalance
    ) internal view returns (uint24[] memory, uint256[] memory) {
        s.ParentPool storage s_parentPool = s.parentPool();

        uint24[] memory childPoolChainSelectors = getChildPoolChainSelectors();
        uint24[] memory chainSelectors = new uint24[](childPoolChainSelectors.length + 1);
        uint256[] memory weights = new uint256[](chainSelectors.length);
        LiqTokenDailyFlow memory dailyFlow;
        uint256 targetBalance;
        uint256 targetBalancesSum;
        uint256 totalWeight;

        chainSelectors[chainSelectors.length - 1] = i_chainSelector;

        for (uint256 i; i < childPoolChainSelectors.length; ++i) {
            chainSelectors[i] = childPoolChainSelectors[i];
            dailyFlow.inflow = _toLocalDecimals(
                s_parentPool.childPoolSnapshots[childPoolChainSelectors[i]].dailyFlow.inflow,
                SCALE_TOKEN_DECIMALS
            );
            dailyFlow.outflow = _toLocalDecimals(
                s_parentPool.childPoolSnapshots[childPoolChainSelectors[i]].dailyFlow.outflow,
                SCALE_TOKEN_DECIMALS
            );

            targetBalance = s_parentPool.childPoolTargetBalances[childPoolChainSelectors[i]];
            targetBalancesSum += targetBalance;

            weights[i] = _calculatePoolWeight(targetBalance, dailyFlow);
            totalWeight += weights[i];
        }

        weights[weights.length - 1] = _calculatePoolWeight(getTargetBalance(), getYesterdayFlow());
        totalWeight += weights[weights.length - 1];

        uint256[] memory newTargetBalances = new uint256[](chainSelectors.length);

        for (uint256 i; i < newTargetBalances.length; ++i) {
            newTargetBalances[i] = _calculateTargetBalance(
                weights[i],
                totalWeight,
                totalLbfBalance
            );
        }

        return (chainSelectors, newTargetBalances);
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
        uint256 targetBalance
    ) internal view returns (uint256) {
        if (targetBalance == 0) return i_liquidityTokenScaleFactor;

        uint256 lur = ((inflow + outflow) * i_liquidityTokenScaleFactor) / targetBalance;

        return
            i_liquidityTokenScaleFactor -
            ((lur * i_liquidityTokenScaleFactor) / (s.parentPool().lurScoreSensitivity + lur));
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
        uint256 targetBalance
    ) internal view returns (uint256) {
        if (inflow >= outflow || targetBalance == 0) return i_liquidityTokenScaleFactor;

        uint256 ndr = ((outflow - inflow) * i_liquidityTokenScaleFactor) / targetBalance;
        return i_liquidityTokenScaleFactor - ndr;
    }

    /// @notice Computes the overall liquidity health score of a pool.
    /// @dev
    /// - Combines LUR and NDR scores using configured weights:
    ///   * `lhs = (lurWeight * lurScore + ndrWeight * ndrScore) / scale`,
    ///   * healthScore = `scale + (scale - lhs)` (higher is healthier).
    /// @param dailyFlow Daily inflow/outflow struct.
    /// @param targetBalance Pool target balance.
    /// @return Liquidity health score.
    function _calculateLiquidityHealthScore(
        LiqTokenDailyFlow memory dailyFlow,
        uint256 targetBalance
    ) internal view returns (uint256) {
        uint256 lurScore = _calculateLiquidityUtilisationRatioScore(
            dailyFlow.inflow,
            dailyFlow.outflow,
            targetBalance
        );

        uint256 ndrScore = _calculateNetDrainRateScore(
            dailyFlow.inflow,
            dailyFlow.outflow,
            targetBalance
        );

        s.ParentPool storage s_parentPool = s.parentPool();

        uint256 lhs = ((s_parentPool.lurScoreWeight * lurScore) +
            (s_parentPool.ndrScoreWeight * ndrScore)) / i_liquidityTokenScaleFactor;

        return i_liquidityTokenScaleFactor + (i_liquidityTokenScaleFactor - lhs);
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
    ) internal pure returns (uint256) {
        return (weight * totalLbfBalance) / totalWeight;
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
        LiqTokenDailyFlow memory dailyFlow
    ) internal view returns (uint256) {
        return
            prevTargetBalance < i_minTargetBalance
                ? (i_minTargetBalance)
                : (prevTargetBalance *
                    _calculateLiquidityHealthScore(dailyFlow, prevTargetBalance)) /
                    i_liquidityTokenScaleFactor;
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
        uint24 dstChainSelector,
        uint256 newTargetBalance
    ) internal {
        s.ParentPool storage s_parentPool = s.parentPool();
        pbs.Base storage s_base = pbs.base();

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
                i_liquidityTokenDecimals
            )
        });

        uint256 messageFee = IConceroRouter(i_conceroRouter).getMessageFee(messageRequest);

        IConceroRouter(i_conceroRouter).conceroSend{value: messageFee}(messageRequest);
    }

    /// @inheritdoc Rebalancer
    /// @notice Rebalancing hook called after positive inflows (e.g. child → parent).
    /// @dev
    /// - Uses inflow to cover pending withdrawals if:
    ///   * `remainingWithdrawalAmount > 0`, and
    ///   * `getActiveBalance() >= targetBalanceFloor`.
    /// - Adjusts:
    ///   * `remainingWithdrawalAmount`,
    ///   * `totalWithdrawalAmountLocked`,
    ///   * base `targetBalance`.
    /// @param inflowLiqTokenAmount Amount of liquidity received.
    function _postInflowRebalance(uint256 inflowLiqTokenAmount) internal override {
        s.ParentPool storage s_parentPool = s.parentPool();

        uint256 remainingWithdrawalAmount = s_parentPool.remainingWithdrawalAmount;

        if (remainingWithdrawalAmount == 0 || getActiveBalance() < s_parentPool.targetBalanceFloor)
            return;

        if (remainingWithdrawalAmount < inflowLiqTokenAmount) {
            delete s_parentPool.remainingWithdrawalAmount;
            delete s_parentPool.targetBalanceFloor;
            s_parentPool.totalWithdrawalAmountLocked += remainingWithdrawalAmount;
            pbs.base().targetBalance -= remainingWithdrawalAmount;
        } else {
            s_parentPool.remainingWithdrawalAmount -= inflowLiqTokenAmount;
            s_parentPool.totalWithdrawalAmountLocked += inflowLiqTokenAmount;
            pbs.base().targetBalance -= inflowLiqTokenAmount;
        }
    }

    /// @notice Checks whether a child pool snapshot timestamp is fresh and valid.
    /// @dev
    /// - Rejects:
    ///   * zero timestamps,
    ///   * timestamps in the future,
    ///   * timestamps older than `CHILD_POOL_SNAPSHOT_EXPIRATION_TIME`.
    /// @param timestamp Snapshot timestamp.
    /// @return True if timestamp is within valid range; otherwise false.
    function _isChildPoolSnapshotTimestampInRange(uint32 timestamp) internal view returns (bool) {
        if ((timestamp == 0) || (timestamp > block.timestamp)) return false;
        return (block.timestamp - timestamp) <= (CHILD_POOL_SNAPSHOT_EXPIRATION_TIME);
    }

    /// @notice Aggregates total pools balance across parent and child pools.
    /// @dev
    /// - Steps:
    ///   1. Collects local stats (parent pool):
    ///      * active balance,
    ///      * IOU totals,
    ///      * total liquidity sent/received.
    ///   2. Converts all local amounts to `SCALE_TOKEN_DECIMALS`.
    ///   3. For each child pool:
    ///      * validates snapshot timestamp range,
    ///      * adds child metrics to totals.
    ///   4. Computes:
    ///      * `iouOnTheWay = totalIouSent - totalIouReceived`,
    ///      * `liqTokenOnTheWay = totalLiqTokenSent - totalLiqTokenReceived`,
    ///      * `totalPoolsBalance = totalPoolsBalance - (liqOnTheWay + iouTotalSupply + iouOnTheWay)`.
    ///   5. Converts `totalPoolsBalance` back to local decimals.
    /// - Returns `(false, 0)` if any snapshot is stale or invalid.
    /// @return success True if all snapshots are valid.
    /// @return totalPoolsBalance Aggregated effective pools balance in local decimals.
    function _getTotalPoolsBalance() internal view returns (bool, uint256) {
        s.ParentPool storage s_parentPool = s.parentPool();
        rs.Rebalancer storage s_rebalancer = rs.rebalancer();
        pbs.Base storage s_poolBase = pbs.base();

        uint24[] memory supportedChainSelectors = s_parentPool.supportedChainSelectors;
        uint256 totalPoolsBalance = getActiveBalance();
        uint256 totalIouSent = s_rebalancer.totalIouSent;
        uint256 totalIouReceived = s_rebalancer.totalIouReceived;
        uint256 iouTotalSupply = i_iouToken.totalSupply();
        uint256 totalLiqTokenSent = s_poolBase.totalLiqTokenSent;
        uint256 totalLiqTokenReceived = s_poolBase.totalLiqTokenReceived;

        totalPoolsBalance = _toScaleDecimals(totalPoolsBalance, i_liquidityTokenDecimals);
        totalIouSent = _toScaleDecimals(totalIouSent, i_liquidityTokenDecimals);
        totalIouReceived = _toScaleDecimals(totalIouReceived, i_liquidityTokenDecimals);
        iouTotalSupply = _toScaleDecimals(iouTotalSupply, i_liquidityTokenDecimals);
        totalLiqTokenSent = _toScaleDecimals(totalLiqTokenSent, i_liquidityTokenDecimals);
        totalLiqTokenReceived = _toScaleDecimals(totalLiqTokenReceived, i_liquidityTokenDecimals);

        for (uint256 i; i < supportedChainSelectors.length; ++i) {
            uint32 snapshotTimestamp = s_parentPool
                .childPoolSnapshots[supportedChainSelectors[i]]
                .timestamp;

            if (!_isChildPoolSnapshotTimestampInRange(snapshotTimestamp)) return (false, 0);

            totalPoolsBalance += s_parentPool
                .childPoolSnapshots[supportedChainSelectors[i]]
                .balance;
            totalIouSent += s_parentPool
                .childPoolSnapshots[supportedChainSelectors[i]]
                .iouTotalSent;
            totalIouReceived += s_parentPool
                .childPoolSnapshots[supportedChainSelectors[i]]
                .iouTotalReceived;
            iouTotalSupply += s_parentPool
                .childPoolSnapshots[supportedChainSelectors[i]]
                .iouTotalSupply;
            totalLiqTokenSent += s_parentPool
                .childPoolSnapshots[supportedChainSelectors[i]]
                .totalLiqTokenSent;
            totalLiqTokenReceived += s_parentPool
                .childPoolSnapshots[supportedChainSelectors[i]]
                .totalLiqTokenReceived;
        }

        uint256 iouOnTheWay = totalIouSent - totalIouReceived;
        uint256 liqTokenOnTheWay = totalLiqTokenSent - totalLiqTokenReceived;

        totalPoolsBalance = totalPoolsBalance - (liqTokenOnTheWay + iouTotalSupply + iouOnTheWay);
        totalPoolsBalance = _toLocalDecimals(totalPoolsBalance, SCALE_TOKEN_DECIMALS);

        return (true, totalPoolsBalance);
    }

    /// @notice Handles incoming child pool snapshots sent via Concero.
    /// @dev
    /// - Decodes snapshot + source decimals via `decodeChildPoolSnapshot`.
    /// - Converts all amounts to `SCALE_TOKEN_DECIMALS` using `_toScaleDecimals`.
    /// - Stores the converted snapshot in `childPoolSnapshots[sourceChainSelector]`.
    /// @param sourceChainSelector Chain selector of the child pool.
    /// @param messageData Encoded snapshot payload.
    function _handleConceroReceiveSnapshot(
        uint24 sourceChainSelector,
        bytes calldata messageData
    ) internal override {
        (ChildPoolSnapshot memory snapshot, uint8 srcDecimals) = messageData
            .decodeChildPoolSnapshot();

        snapshot.balance = _toScaleDecimals(snapshot.balance, srcDecimals);

        snapshot.dailyFlow = IBase.LiqTokenDailyFlow({
            inflow: _toScaleDecimals(snapshot.dailyFlow.inflow, srcDecimals),
            outflow: _toScaleDecimals(snapshot.dailyFlow.outflow, srcDecimals)
        });
        snapshot.iouTotalSent = _toScaleDecimals(snapshot.iouTotalSent, srcDecimals);
        snapshot.iouTotalReceived = _toScaleDecimals(snapshot.iouTotalReceived, srcDecimals);
        snapshot.iouTotalSupply = _toScaleDecimals(snapshot.iouTotalSupply, srcDecimals);
        snapshot.totalLiqTokenSent = _toScaleDecimals(snapshot.totalLiqTokenSent, srcDecimals);
        snapshot.totalLiqTokenReceived = _toScaleDecimals(
            snapshot.totalLiqTokenReceived,
            srcDecimals
        );

        s.parentPool().childPoolSnapshots[sourceChainSelector] = snapshot;
    }

    /// @dev
    /// - Parent pool does not accept `UPDATE_TARGET_BALANCE` messages (it is the source of truth).
    /// - Always reverts with `FunctionNotImplemented`.
    function _handleConceroReceiveUpdateTargetBalance(bytes calldata) internal pure override {
        revert ICommonErrors.FunctionNotImplemented();
    }

    /// @notice Converts an amount from arbitrary decimals to the internal scale decimals.
    /// @dev Uses `Decimals.toDecimals` helper under the hood.
    /// @param amountInSrcDecimals Amount in source decimals.
    /// @param srcDecimals Source token decimals.
    /// @return Amount scaled to `SCALE_TOKEN_DECIMALS`.
    function _toScaleDecimals(
        uint256 amountInSrcDecimals,
        uint8 srcDecimals
    ) internal pure returns (uint256) {
        return amountInSrcDecimals.toDecimals(srcDecimals, SCALE_TOKEN_DECIMALS);
    }
}
