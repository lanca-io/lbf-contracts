// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {ConceroTypes} from "@concero/v2-contracts/contracts/ConceroClient/ConceroTypes.sol";
import {ICommonErrors} from "../common/interfaces/ICommonErrors.sol";
import {IConceroRouter} from "@concero/v2-contracts/contracts/interfaces/IConceroRouter.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ILancaKeeper} from "./interfaces/ILancaKeeper.sol";
import {IParentPool} from "./interfaces/IParentPool.sol";
import {LPToken} from "./LPToken.sol";
import {PoolBase} from "../PoolBase/PoolBase.sol";
import {Rebalancer} from "../Rebalancer/Rebalancer.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Storage as pbs} from "../PoolBase/libraries/Storage.sol";
import {Storage as rs} from "../Rebalancer/libraries/Storage.sol";
import {Storage as s} from "./libraries/Storage.sol";
import {LancaBridge} from "../LancaBridge/LancaBridge.sol";

contract ParentPool is IParentPool, ILancaKeeper, Rebalancer, LancaBridge {
    using s for s.ParentPool;
    using rs for rs.Rebalancer;
    using pbs for pbs.PoolBase;
    using SafeERC20 for IERC20;

    error ChildPoolSnapshotsAreNotReady();
    error InvalidLiqTokenDecimals();

    uint32 internal constant UPDATE_TARGET_BALANCE_MESSAGE_GAS_LIMIT = 100_000;

    LPToken internal immutable i_lpToken;
    uint8 private immutable i_lpTokenDecimals;
    uint256 internal immutable i_minTargetBalance;

    constructor(
        address liquidityToken,
        uint8 liquidityTokenDecimals,
        address lpToken,
        address conceroRouter,
        uint24 chainSelector,
        address iouToken,
        uint256 minTargetBalance
    )
        PoolBase(liquidityToken, conceroRouter, iouToken, liquidityTokenDecimals, chainSelector)
        Rebalancer()
    {
        i_lpToken = LPToken(lpToken);
        i_lpTokenDecimals = i_lpToken.decimals();
        // todo: move it to only one var
        require(i_lpTokenDecimals == liquidityTokenDecimals, InvalidLiqTokenDecimals());

        i_minTargetBalance = minTargetBalance;
    }

    receive() external payable {}

    function enterDepositQueue(uint256 liquidityTokenAmount) external {
        require(liquidityTokenAmount > 0, ICommonErrors.InvalidAmount());

        s.ParentPool storage s_parentPool = s.parentPool();
        require(
            s_parentPool.depositsQueueIds.length < s_parentPool.targetDepositQueueLength,
            DepositQueueIsFull()
        );

        IERC20(i_liquidityToken).safeTransferFrom(msg.sender, address(this), liquidityTokenAmount);

        Deposit memory deposit = Deposit({
            liquidityTokenAmountToDeposit: liquidityTokenAmount,
            lp: msg.sender
        });
        bytes32 depositId = keccak256(
            abi.encodePacked(msg.sender, block.number, ++s_parentPool.depositNonce)
        );

        s_parentPool.depositsQueue[depositId] = deposit;
        s_parentPool.depositsQueueIds.push(depositId);
        s_parentPool.totalDepositAmountInQueue += liquidityTokenAmount;

        emit DepositQueued(depositId, deposit.lp, liquidityTokenAmount);
    }

    function enterWithdrawQueue(uint256 lpTokenAmount) external {
        require(lpTokenAmount > 0, ICommonErrors.InvalidAmount());

        s.ParentPool storage s_parentPool = s.parentPool();

        require(
            s_parentPool.withdrawalsQueueIds.length < s_parentPool.targetWithdrawalQueueLength,
            WithdrawalQueueIsFull()
        );

        IERC20(i_lpToken).safeTransferFrom(msg.sender, address(this), lpTokenAmount);

        Withdrawal memory withdraw = Withdrawal({
            lpTokenAmountToWithdraw: lpTokenAmount,
            lp: msg.sender
        });
        bytes32 withdrawId = keccak256(
            abi.encodePacked(msg.sender, block.number, ++s_parentPool.withdrawalNonce)
        );

        s_parentPool.withdrawalsQueue[withdrawId] = withdraw;
        s_parentPool.withdrawalsQueueIds.push(withdrawId);

        emit WithdrawQueued(withdrawId, withdraw.lp, lpTokenAmount);
    }

    function _handleConceroReceiveSnapshot(
        bytes32 messageId,
        uint24 sourceChainSelector,
        bytes memory messageData
    ) internal override {
        (IParentPool.SnapshotSubmission memory snapshot) = abi.decode(
            messageData,
            (IParentPool.SnapshotSubmission)
        );

        s.parentPool().childPoolsSubmissions[sourceChainSelector] = snapshot;

        emit IParentPool.SnapshotReceived(messageId, sourceChainSelector, snapshot);
    }

    function getChildPoolChainSelectors() public view returns (uint24[] memory) {
        return s.parentPool().supportedChainSelectors;
    }

    function isReadyToTriggerDepositWithdrawProcess() external view returns (bool) {
        (bool success, ) = _getTotalLbfBalance();
        return success && areQueuesFull();
    }

    function areQueuesFull() public view returns (bool) {
        s.ParentPool storage s_parentPool = s.parentPool();
        return
            s_parentPool.withdrawalsQueueIds.length == s_parentPool.targetWithdrawalQueueLength &&
            s_parentPool.depositsQueueIds.length == s_parentPool.targetDepositQueueLength;
    }

    function isReadyToProcessPendingWithdrawals() public view returns (bool) {
        s.ParentPool storage s_parentPool = s.parentPool();
        return
            (s_parentPool.remainingWithdrawalAmount == 0) &&
            (s_parentPool.totalWithdrawalAmountLocked > 0);
    }

    function getActiveBalance() public view override returns (uint256) {
        s.ParentPool storage s_parentPool = s.parentPool();
        return
            super.getActiveBalance() -
            s_parentPool.totalDepositAmountInQueue -
            s_parentPool.totalWithdrawalAmountLocked;
    }

    function getWithdrawalFee(uint256 amount) public view returns (uint256, uint256) {
        s.ParentPool storage s_parentPool = s.parentPool();
        uint256 pendingWithdrawalCount = s_parentPool.pendingWithdrawalIds.length;

        if (pendingWithdrawalCount == 0) {
            return (0, getRebalancerFee(amount));
        }

        /* @dev We multiply this by 4 because we collect the fee from
                the user upon withdrawal for both deposits
                and withdrawals, and when depositing or withdrawing,
                messages are sent twice: first childPools ->
                parentPool, then parentPool -> childPools */
        uint256 conceroFee = (s_parentPool.averageConceroMessageFee *
            getChildPoolChainSelectors().length *
            4) / pendingWithdrawalCount;

        return (conceroFee, getRebalancerFee(amount));
    }

    function getTargetDepositQueueLength() public view returns (uint16) {
        return s.parentPool().targetDepositQueueLength;
    }

    function getTargetWithdrawalQueueLength() public view returns (uint16) {
        return s.parentPool().targetWithdrawalQueueLength;
    }

    function triggerDepositWithdrawProcess() external onlyLancaKeeper {
        require(areQueuesFull(), QueuesAreNotFull());

        (bool areChildPoolSnapshotsReady, uint256 totalPoolsBalance) = _getTotalLbfBalance();
        require(areChildPoolSnapshotsReady, ChildPoolSnapshotsAreNotReady());

        s.ParentPool storage s_parentPool = s.parentPool();

        uint256 deposited = _processDepositsQueue(totalPoolsBalance);
        uint256 withdrawals = _processWithdrawalsQueue(totalPoolsBalance);
        uint256 newTotalBalance = totalPoolsBalance + deposited;
        uint256 totalRequestedWithdrawals = s_parentPool.remainingWithdrawalAmount + withdrawals;

        (deposited >= totalRequestedWithdrawals)
            ? _processInflow(newTotalBalance, totalRequestedWithdrawals)
            : _processOutflow(newTotalBalance, totalRequestedWithdrawals);
    }

    function processPendingWithdrawals() external onlyLancaKeeper {
        s.ParentPool storage s_parentPool = s.parentPool();
        require(
            isReadyToProcessPendingWithdrawals(),
            PendingWithdrawalsAreNotReady(
                s_parentPool.remainingWithdrawalAmount,
                s_parentPool.totalWithdrawalAmountLocked
            )
        );

        bytes32[] memory pendingWithdrawalIds = s_parentPool.pendingWithdrawalIds;
        PendingWithdrawal memory pendingWithdrawal;
        uint256 totalLiquidityTokenAmountToWithdraw;
        uint256 totalLancaFee;
        uint256 totalRebalanceFee;

        for (uint256 i; i < pendingWithdrawalIds.length; ++i) {
            pendingWithdrawal = s_parentPool.pendingWithdrawals[pendingWithdrawalIds[i]];
            delete s_parentPool.pendingWithdrawals[pendingWithdrawalIds[i]];
            i_lpToken.burn(pendingWithdrawal.lpTokenAmountToWithdraw);

            (uint256 conceroFee, uint256 rebalanceFee) = getWithdrawalFee(
                pendingWithdrawal.liqTokenAmountToWithdraw
            );
            uint256 amountToWithdrawWithFee = pendingWithdrawal.liqTokenAmountToWithdraw -
                (conceroFee + rebalanceFee);

            IERC20(i_liquidityToken).safeTransfer(pendingWithdrawal.lp, amountToWithdrawWithFee);
            totalLiquidityTokenAmountToWithdraw += amountToWithdrawWithFee;
            totalLancaFee += conceroFee;
            totalRebalanceFee += rebalanceFee;
        }

        /* @dev do not clear this array in a loop because
                clearing it will affect getWithdrawalFee() */
        delete s_parentPool.pendingWithdrawalIds;

        s_parentPool.totalWithdrawalAmountLocked -= totalLiquidityTokenAmountToWithdraw;
        s_parentPool.totalLancaFeeInLiqToken += totalLancaFee;
        rs.rebalancer().totalRebalancingFee += totalRebalanceFee;
    }

    /*   ADMIN FUNCTIONS   */

    function setTargetDepositQueueLength(uint16 length) external onlyOwner {
        s.parentPool().targetDepositQueueLength = length;
    }

    function setTargetWithdrawalQueueLength(uint16 length) external onlyOwner {
        s.parentPool().targetWithdrawalQueueLength = length;
    }

    function setDstPool(uint24 chainSelector, address dstPool) public override onlyOwner {
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

    /*   INTERNAL FUNCTIONS   */

    function _processDepositsQueue(uint256 totalPoolsBalance) internal returns (uint256) {
        s.ParentPool storage s_parentPool = s.parentPool();

        bytes32[] memory depositsQueueIds = s_parentPool.depositsQueueIds;
        uint256 totalDepositedLiqTokenAmount;
        uint256 amountToDepositWithFee;
        uint256 depositFee;
        uint256 totalDepositFee;

        for (uint256 i; i < depositsQueueIds.length; ++i) {
            Deposit memory deposit = s_parentPool.depositsQueue[depositsQueueIds[i]];

            delete s_parentPool.depositsQueue[depositsQueueIds[i]];

            depositFee = getRebalancerFee(deposit.liquidityTokenAmountToDeposit);
            amountToDepositWithFee = deposit.liquidityTokenAmountToDeposit - depositFee;
            totalDepositFee += depositFee;

            uint256 lpTokenAmountToMint = _calculateLpTokenAmountToMint(
                totalPoolsBalance + totalDepositedLiqTokenAmount,
                amountToDepositWithFee
            );

            // TODO: may be more gas-optimal if you subtract one time outside the cycle
            s_parentPool.totalDepositAmountInQueue -= deposit.liquidityTokenAmountToDeposit;
            LPToken(i_lpToken).mint(deposit.lp, lpTokenAmountToMint);
            totalDepositedLiqTokenAmount += amountToDepositWithFee;
        }

        delete s_parentPool.depositsQueueIds;
        rs.rebalancer().totalRebalancingFee += totalDepositFee;

        return totalDepositedLiqTokenAmount;
    }

    function _processWithdrawalsQueue(uint256 totalPoolsBalance) internal returns (uint256) {
        s.ParentPool storage s_parentPool = s.parentPool();

        bytes32[] memory withdrawalsQueueIds = s_parentPool.withdrawalsQueueIds;
        uint256 totalLiqTokenAmountToWithdraw;
        uint256 liqTokenAmountToWithdraw;
        Withdrawal memory withdrawal;

        for (uint256 i; i < withdrawalsQueueIds.length; ++i) {
            withdrawal = s_parentPool.withdrawalsQueue[withdrawalsQueueIds[i]];

            delete s_parentPool.withdrawalsQueue[withdrawalsQueueIds[i]];

            liqTokenAmountToWithdraw = _calculateWithdrawableAmount(
                totalPoolsBalance - totalLiqTokenAmountToWithdraw,
                withdrawal.lpTokenAmountToWithdraw
            );

            totalLiqTokenAmountToWithdraw += liqTokenAmountToWithdraw;

            s_parentPool.pendingWithdrawals[withdrawalsQueueIds[i]] = PendingWithdrawal({
                liqTokenAmountToWithdraw: liqTokenAmountToWithdraw,
                lpTokenAmountToWithdraw: withdrawal.lpTokenAmountToWithdraw,
                lp: withdrawal.lp
            });
            s_parentPool.pendingWithdrawalIds.push(withdrawalsQueueIds[i]);
        }

        delete s_parentPool.withdrawalsQueueIds;

        return totalLiqTokenAmountToWithdraw;
    }

    function _processInflow(uint256 totalLbfBalance, uint256 totalRequestedWithdrawals) internal {
        s.ParentPool storage s_parentPool = s.parentPool();

        (
            uint24[] memory chainSelectors,
            uint256[] memory targetBalances
        ) = _calculateNewTargetBalances(totalLbfBalance);

        s_parentPool.totalWithdrawalAmountLocked += totalRequestedWithdrawals;
        delete s_parentPool.remainingWithdrawalAmount;

        for (uint256 i; i < chainSelectors.length; ++i) {
            // @dev check if it is child pool chain selector
            if (chainSelectors[i] != i_chainSelector) {
                _updateChildPoolTargetBalance(chainSelectors[i], targetBalances[i]);

                /* @dev we only delete the timestamp because
                        that is enough to prevent it from passing
                        _isChildPoolSnapshotTimestampInRange(snapshotTimestamp)
                        and being used a second time */
                delete s_parentPool.childPoolsSubmissions[chainSelectors[i]].timestamp;
            } else {
                pbs.poolBase().targetBalance += targetBalances[i];
            }
        }
    }

    function _processOutflow(uint256 totalLbfBalance, uint256 totalRequested) internal {
        uint256 surplus = getSurplus();
        uint256 coveredBySurplus = surplus >= totalRequested ? totalRequested : surplus;

        s.ParentPool storage s_parentPool = s.parentPool();

        (
            uint24[] memory chainSelectors,
            uint256[] memory targetBalances
        ) = _calculateNewTargetBalances(totalLbfBalance - coveredBySurplus);

        for (uint256 i; i < chainSelectors.length; ++i) {
            // @dev check if it is child pool chain selector
            if (chainSelectors[i] != i_chainSelector) {
                _updateChildPoolTargetBalance(chainSelectors[i], targetBalances[i]);

                /* @dev we only delete the timestamp because
                        that is enough to prevent it from passing
                        _isChildPoolSnapshotTimestampInRange(snapshotTimestamp)
                        and being used a second time */
                delete s_parentPool.childPoolsSubmissions[chainSelectors[i]].timestamp;
            } else {
                uint256 remaining = totalRequested - coveredBySurplus;

                s_parentPool.totalWithdrawalAmountLocked += coveredBySurplus;
                s_parentPool.remainingWithdrawalAmount = remaining;
                s_parentPool.minParentPoolTargetBalance = targetBalances[i];

                pbs.poolBase().targetBalance += remaining;
            }
        }
    }

    function _calculateLpTokenAmountToMint(
        uint256 totalLbfActiveBalance,
        uint256 liquidityTokenAmountToDeposit
    ) internal view returns (uint256) {
        uint256 lpTokenTotalSupply = IERC20(i_lpToken).totalSupply();

        if (lpTokenTotalSupply == 0) return liquidityTokenAmountToDeposit;

        return (lpTokenTotalSupply * liquidityTokenAmountToDeposit) / totalLbfActiveBalance;
    }

    function _calculateWithdrawableAmount(
        uint256 totalPoolsBalance,
        uint256 lpTokenAmount
    ) internal view returns (uint256) {
        // @dev USDC_WITHDRAWABLE = POOL_BALANCE x (LP_INPUT_AMOUNT / TOTAL_LP)
        return (totalPoolsBalance * lpTokenAmount) / i_lpToken.totalSupply();
    }

    function _calculateNewTargetBalances(
        uint256 totalLbfBalance
    ) internal view returns (uint24[] memory, uint256[] memory) {
        s.ParentPool storage s_parentPool = s.parentPool();

        uint24[] memory childPoolChainSelectors = getChildPoolChainSelectors();
        uint24[] memory chainSelectors = new uint24[](childPoolChainSelectors.length + 1);
        uint256[] memory weights = new uint256[](chainSelectors.length);
        LiqTokenDailyFlow memory dailyFlow;
        uint256 tagetBalance;
        uint256 targetBalancesSum;
        uint256 totalWeight;

        chainSelectors[chainSelectors.length - 1] = i_chainSelector;

        for (uint256 i; i < childPoolChainSelectors.length; ++i) {
            chainSelectors[i] = childPoolChainSelectors[i];
            dailyFlow = s_parentPool.childPoolsSubmissions[childPoolChainSelectors[i]].dailyFlow;

            tagetBalance = s_parentPool.childPoolTargetBalances[childPoolChainSelectors[i]];
            targetBalancesSum += tagetBalance;

            weights[i] = tagetBalance < i_minTargetBalance
                ? (i_minTargetBalance)
                : tagetBalance * _calculateLiquidityHealthScore(dailyFlow, tagetBalance);
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

        return (chainSelectors, newTargetBalances);
    }

    function _calculateLiquidityUtilisationRatioScore(
        uint256 inflow,
        uint256 outflow,
        uint256 tagetBalance
    ) internal view returns (uint8) {
        if (tagetBalance == 0) return 1;
        uint256 lur = (inflow + outflow) / tagetBalance;
        return uint8(1 - (lur / (s.parentPool().lhsCalculationFactors.lurScoreSensitivity + lur)));
    }

    function _calculateNetDrainRateScore(
        uint256 inflow,
        uint256 outflow,
        uint256 tagetBalance
    ) internal pure returns (uint8) {
        if (inflow >= outflow || tagetBalance == 0) return 1;

        uint256 ndr = (outflow - inflow) / tagetBalance;
        return uint8(1 - ndr);
    }

    function _calculateLiquidityHealthScore(
        LiqTokenDailyFlow memory dailyFlow,
        uint256 tagetBalance
    ) internal view returns (uint8) {
        uint8 lurScore = _calculateLiquidityUtilisationRatioScore(
            dailyFlow.inflow,
            dailyFlow.outflow,
            tagetBalance
        );
        uint8 ndrScore = _calculateNetDrainRateScore(
            dailyFlow.inflow,
            dailyFlow.outflow,
            tagetBalance
        );
        s.ParentPool storage s_parentPool = s.parentPool();

        uint8 lhs = (s_parentPool.lhsCalculationFactors.lurScoreWeight * lurScore) +
            (s_parentPool.lhsCalculationFactors.ndrScoreWeight * ndrScore);

        return 1 + (1 - lhs);
    }

    function _calculateTargetBalance(
        uint256 weight,
        uint256 totalWeight,
        uint256 totalLbfBalance
    ) internal pure returns (uint256) {
        return (weight * totalLbfBalance) / totalWeight;
    }

    function _calculateParentPoolTargetBalanceWeight() internal view returns (uint256) {
        uint256 targetBalance = getTargetBalance();
        return
            targetBalance < i_minTargetBalance
                ? (i_minTargetBalance)
                : targetBalance * _calculateLiquidityHealthScore(getYesterdayFlow(), targetBalance);
    }

    function _updateChildPoolTargetBalance(
        uint24 dstChainSelector,
        uint256 newTargetBalance
    ) internal {
        s.ParentPool storage s_parentPool = s.parentPool();

        if (s_parentPool.childPoolTargetBalances[dstChainSelector] == newTargetBalance) return;
        s_parentPool.childPoolTargetBalances[dstChainSelector] = newTargetBalance;

        address childPool = pbs.poolBase().dstPools[dstChainSelector];
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

    // TODO: mb it has to be virtual function in rebalancer
    function _postInflowRebalance(uint256 inflowLiqTokenAmount) internal {
        s.ParentPool storage s_parentPool = s.parentPool();

        uint256 remainingWithdrawalAmount = s_parentPool.remainingWithdrawalAmount;

        if (remainingWithdrawalAmount == 0) return;
        // TODO: add min target balance check

        if (remainingWithdrawalAmount < inflowLiqTokenAmount) {
            delete s_parentPool.remainingWithdrawalAmount;
            s_parentPool.totalWithdrawalAmountLocked += remainingWithdrawalAmount;
            pbs.poolBase().targetBalance -= remainingWithdrawalAmount;
        } else {
            s_parentPool.remainingWithdrawalAmount -= inflowLiqTokenAmount;
            s_parentPool.totalWithdrawalAmountLocked += inflowLiqTokenAmount;
            pbs.poolBase().targetBalance -= inflowLiqTokenAmount;
        }
    }

    function _isChildPoolSnapshotTimestampInRange(uint32 timestamp) internal view returns (bool) {
        if ((timestamp == 0) || (timestamp > block.timestamp)) return false;
        return (block.timestamp - timestamp) <= (30 minutes);
    }

    function _getTotalLbfBalance() internal view returns (bool, uint256) {
        s.ParentPool storage s_parentPool = s.parentPool();
        rs.Rebalancer storage s_rebalancer = rs.rebalancer();

        uint24[] memory supportedChainSelectors = s_parentPool.supportedChainSelectors;
        uint256 totalPoolsBalance = getActiveBalance();
        uint256 totalIouSent = s_rebalancer.totalIouSent;
        uint256 totalIouReceived = s_rebalancer.totalIouReceived;
        uint256 iouTotalSupply = i_iouToken.totalSupply();

        for (uint256 i; i < supportedChainSelectors.length; ++i) {
            uint32 snapshotTimestamp = s_parentPool
                .childPoolsSubmissions[supportedChainSelectors[i]]
                .timestamp;

            if (!_isChildPoolSnapshotTimestampInRange(snapshotTimestamp)) return (false, 0);

            totalPoolsBalance += s_parentPool
                .childPoolsSubmissions[supportedChainSelectors[i]]
                .balance;
            totalIouSent += s_parentPool
                .childPoolsSubmissions[supportedChainSelectors[i]]
                .iouTotalSent;
            totalIouReceived += s_parentPool
                .childPoolsSubmissions[supportedChainSelectors[i]]
                .iouTotalReceived;
            iouTotalSupply += s_parentPool
                .childPoolsSubmissions[supportedChainSelectors[i]]
                .iouTotalSupply;
        }

        uint256 iouOnTheWay = totalIouSent - totalIouReceived;

        return (true, totalPoolsBalance - (iouTotalSupply + iouOnTheWay));
    }
}
