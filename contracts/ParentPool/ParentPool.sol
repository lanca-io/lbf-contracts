// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {BridgeCodec} from "../common/libraries/BridgeCodec.sol";
import {Decimals} from "../common/libraries/Decimals.sol";
import {ICommonErrors} from "../common/interfaces/ICommonErrors.sol";
import {ILancaKeeper} from "./interfaces/ILancaKeeper.sol";
import {IParentPool} from "./interfaces/IParentPool.sol";
import {ParentPoolLib} from "./libraries/ParentPoolLib.sol";
import {Rebalancer} from "../Rebalancer/Rebalancer.sol";
import {LancaBridge} from "../LancaBridge/LancaBridge.sol";
import {Storage as s} from "./libraries/Storage.sol";
import {Storage as rs} from "../Rebalancer/libraries/Storage.sol";
import {Storage as pbs} from "../Base/libraries/Storage.sol";
import {IBase} from "../Base/interfaces/IBase.sol";
import {Base} from "../Base/Base.sol";
import {LPToken} from "./LPToken.sol";

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
    using BridgeCodec for bytes;
    using Decimals for uint256;

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
        ParentPoolLib.enterDepositQueue(s.parentPool(), liquidityTokenAmount, i_liquidityToken);
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
        ParentPoolLib.enterWithdrawalQueue(s.parentPool(), lpTokenAmount, address(i_lpToken));
    }

    /// @inheritdoc ILancaKeeper
    /// @notice Processes deposit and withdrawal queues and rebalances pool targets.
    /// @dev
    /// - Only callable by `LANCA_KEEPER`.
    /// - Steps:
    ///   1. Ensures deposit and withdrawal queues meet minimum lengths (`areQueuesFull()`).
    ///   2. Aggregates total pools balance from parent + all child pools (`_getTotalPoolsBalance`).
    ///   3. Processes deposits queue via `ParentPoolLib::_processDepositsQueue`.
    ///   4. Processes withdrawals queue via `ParentPoolLib::_processWithdrawalsQueue`.
    ///   5. Updates target balances across pools and locks withdrawals via `ParentPoolLib::_updateChildPoolTargetBalances`.
    function triggerDepositWithdrawProcess() external onlyRole(LANCA_KEEPER) {
        require(areQueuesFull(), QueuesAreNotFull());

        s.ParentPool storage s_parentPool = s.parentPool();

        ParentPoolLib.triggerDepositWithdrawalProcess(
            s_parentPool,
            rs.rebalancer(),
            pbs.base(),
            ParentPoolLib.TriggerProcessParams({
                activeBalance: getActiveBalance(),
                iouToken: address(i_iouToken),
                lpToken: address(i_lpToken),
                conceroRouter: i_conceroRouter,
                liquidityTokenDecimals: i_liquidityTokenDecimals,
                parentChainSelector: i_chainSelector,
                lurScoreSensitivity: s_parentPool.lurScoreSensitivity,
                lurScoreWeight: s_parentPool.lurScoreWeight,
                ndrScoreWeight: s_parentPool.ndrScoreWeight,
                liquidityTokenScaleFactor: i_liquidityTokenScaleFactor,
                minTargetBalance: i_minTargetBalance,
                parentTargetBalance: getTargetBalance(),
                parentYesterdayFlow: getYesterdayFlow()
            }),
            this.getActiveBalance,
            this.getRebalancerFee
        );
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

        ParentPoolLib.processPendingWithdrawals(
            s_parentPool,
            rs.rebalancer(),
            pbs.base(),
            i_liquidityToken,
            address(i_lpToken),
            this.safeTransferWrapper,
            this.getWithdrawalFee
        );
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
        return
            ParentPoolLib.calculateWithdrawableAmount(
                totalPoolsBalance,
                lpTokenAmount,
                address(i_lpToken)
            );
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

        bool exists = false;
        for (uint256 i; i < supportedChainSelectors.length; ++i) {
            if (supportedChainSelectors[i] == chainSelector) {
                exists = true;
                break;
            }
        }

        if (!exists) {
            s_parentPool.supportedChainSelectors.push(chainSelector);
        }
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
        return
            ParentPoolLib.getTotalPoolsBalance(
                s.parentPool(),
                rs.rebalancer(),
                pbs.base(),
                getActiveBalance(),
                i_iouToken.totalSupply(),
                i_liquidityTokenDecimals
            );
    }

    /// @notice Handles incoming child pool snapshots sent via Concero.
    /// @dev
    /// - Decodes snapshot + source decimals via `decodeChildPoolSnapshot`.
    /// - Converts all amounts to `SCALE_TOKEN_DECIMALS` using `_toScaleDecimals`.
    /// - Checks if the snapshot is newer than the existing one.
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

        if (snapshot.timestamp > s.parentPool().childPoolSnapshots[sourceChainSelector].timestamp) {
            s.parentPool().childPoolSnapshots[sourceChainSelector] = snapshot;
        }
    }

    /// @dev
    /// - Parent pool does not accept `UPDATE_TARGET_BALANCE` messages (it is the source of truth).
    /// - Always reverts with `FunctionNotImplemented`.
    function _handleConceroReceiveUpdateTargetBalance(
        uint24,
        bytes calldata
    ) internal pure override {
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
