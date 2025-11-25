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
import {IBase} from "../Base/interfaces/IBase.sol";

import {console} from "forge-std/src/console.sol";

contract ParentPool is IParentPool, ILancaKeeper, Rebalancer, LancaBridge {
    using s for s.ParentPool;
    using rs for rs.Rebalancer;
    using pbs for pbs.Base;
    using SafeERC20 for IERC20;
    using BridgeCodec for bytes32;
    using BridgeCodec for bytes;

    uint32 internal constant UPDATE_TARGET_BALANCE_MESSAGE_GAS_LIMIT = 100_000;
    uint32 internal constant CHILD_POOL_SNAPSHOT_EXPIRATION_TIME = 10 minutes;
    uint8 internal constant MAX_QUEUE_LENGTH = 250;

    LPToken internal immutable i_lpToken;
    uint256 internal immutable i_liquidityTokenScaleFactor;
    uint256 internal immutable i_minTargetBalance;

    constructor(
        address liquidityToken,
        address lpToken,
        address iouToken,
        address conceroRouter,
        uint24 chainSelector,
        // todo: mb move to storage
        uint256 minTargetBalance
    ) Base(liquidityToken, conceroRouter, iouToken, chainSelector) {
        i_lpToken = LPToken(lpToken);

        uint8 liquidityTokenDecimals = IERC20Metadata(liquidityToken).decimals();
        require(i_lpToken.decimals() == liquidityTokenDecimals, InvalidLiqTokenDecimals());

        i_minTargetBalance = minTargetBalance;
        i_liquidityTokenScaleFactor = 10 ** liquidityTokenDecimals;
    }

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

    function enterWithdrawalQueue(uint256 lpTokenAmount) external {
        require(lpTokenAmount > 0, ICommonErrors.AmountIsZero());

        s.ParentPool storage s_parentPool = s.parentPool();

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

    function triggerDepositWithdrawProcess() external onlyLancaKeeper {
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
        s_parentPool.totalLancaFeeInLiqToken += totalLancaFee;
    }

    function safeTransferWrapper(address token, address to, uint256 amount) external {
        require(msg.sender == address(this), OnlySelf());
        IERC20(token).safeTransfer(to, amount);
    }

    /*   VIEW FUNCTIONS   */

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

    function isReadyToTriggerDepositWithdrawProcess() external view returns (bool) {
        (bool success, ) = _getTotalPoolsBalance();
        return success && areQueuesFull();
    }

    function areQueuesFull() public view returns (bool) {
        s.ParentPool storage s_parentPool = s.parentPool();

        uint256 withdrawalLength = s_parentPool.withdrawalQueueIds.length;
        uint256 depositLength = s_parentPool.depositQueueIds.length;

        if ((depositLength == 0) && withdrawalLength == 0) return false;

        return
            withdrawalLength >= s_parentPool.minWithdrawalQueueLength &&
            depositLength >= s_parentPool.minDepositQueueLength;
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

    function getWithdrawableAmount(
        uint256 totalPoolsBalance,
        uint256 lpTokenAmount
    ) public view returns (uint256) {
        return _calculateWithdrawableAmount(totalPoolsBalance, lpTokenAmount);
    }

    /*   ADMIN FUNCTIONS   */

    function setMinDepositQueueLength(uint16 length) external onlyOwner {
        s.parentPool().minDepositQueueLength = length;
    }

    function setMinWithdrawalQueueLength(uint16 length) external onlyOwner {
        s.parentPool().minWithdrawalQueueLength = length;
    }

    function setDstPool(uint24 chainSelector, bytes32 dstPool) public override onlyOwner {
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

    // TODO: add remove dst pool

    function setLurScoreSensitivity(uint64 lurScoreSensitivity) external onlyOwner {
        require(
            (lurScoreSensitivity > i_liquidityTokenScaleFactor) &&
                (lurScoreSensitivity < (10 * i_liquidityTokenScaleFactor)),
            InvalidLurScoreSensitivity()
        );
        s.parentPool().lurScoreSensitivity = lurScoreSensitivity;
    }

    function setScoresWeights(uint64 lurScoreWeight, uint64 ndrScoreWeight) external onlyOwner {
        require(
            lurScoreWeight + ndrScoreWeight == i_liquidityTokenScaleFactor,
            InvalidScoreWeights()
        );

        s.ParentPool storage s_parentPool = s.parentPool();

        s_parentPool.lurScoreWeight = lurScoreWeight;
        s_parentPool.ndrScoreWeight = ndrScoreWeight;
    }

    function setLiquidityCap(uint256 newLiqCap) external onlyOwner {
        s.parentPool().liquidityCap = newLiqCap;
    }

    function setMinDepositAmount(uint64 newMinDepositAmount) external onlyOwner {
        s.parentPool().minDepositAmount = newMinDepositAmount;
    }

    function setAverageConceroMessageFee(uint96 averageConceroMessageFee) external onlyOwner {
        s.parentPool().averageConceroMessageFee = averageConceroMessageFee;
    }

    /*   INTERNAL FUNCTIONS   */

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
        uint256 targetBalance;
        uint256 targetBalancesSum;
        uint256 totalWeight;

        chainSelectors[chainSelectors.length - 1] = i_chainSelector;

        for (uint256 i; i < childPoolChainSelectors.length; ++i) {
            chainSelectors[i] = childPoolChainSelectors[i];
            dailyFlow = s_parentPool.childPoolSnapshots[childPoolChainSelectors[i]].dailyFlow;

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

    function _calculateNetDrainRateScore(
        uint256 inflow,
        uint256 outflow,
        uint256 targetBalance
    ) internal view returns (uint256) {
        if (inflow >= outflow || targetBalance == 0) return i_liquidityTokenScaleFactor;

        uint256 ndr = ((outflow - inflow) * i_liquidityTokenScaleFactor) / targetBalance;
        return i_liquidityTokenScaleFactor - ndr;
    }

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

    function _calculateTargetBalance(
        uint256 weight,
        uint256 totalWeight,
        uint256 totalLbfBalance
    ) internal pure returns (uint256) {
        return (weight * totalLbfBalance) / totalWeight;
    }

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

    function _isChildPoolSnapshotTimestampInRange(uint32 timestamp) internal view returns (bool) {
        if ((timestamp == 0) || (timestamp > block.timestamp)) return false;
        return (block.timestamp - timestamp) <= (CHILD_POOL_SNAPSHOT_EXPIRATION_TIME);
    }

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

        return (true, totalPoolsBalance - (liqTokenOnTheWay + iouTotalSupply + iouOnTheWay));
    }

    function _handleConceroReceiveSnapshot(
        uint24 sourceChainSelector,
        bytes calldata messageData
    ) internal override {
        (ChildPoolSnapshot memory snapshot, uint8 srcDecimals) = messageData
            .decodeChildPoolSnapshot();

        console.log(srcDecimals);

        snapshot.balance = _toLocalDecimals(snapshot.balance, srcDecimals);

        console.log(snapshot.balance);

        snapshot.dailyFlow = IBase.LiqTokenDailyFlow({
            inflow: _toLocalDecimals(snapshot.dailyFlow.inflow, srcDecimals),
            outflow: _toLocalDecimals(snapshot.dailyFlow.outflow, srcDecimals)
        });
        snapshot.iouTotalSent = _toLocalDecimals(snapshot.iouTotalSent, srcDecimals);
        snapshot.iouTotalReceived = _toLocalDecimals(snapshot.iouTotalReceived, srcDecimals);
        snapshot.iouTotalSupply = _toLocalDecimals(snapshot.iouTotalSupply, srcDecimals);
        snapshot.totalLiqTokenSent = _toLocalDecimals(snapshot.totalLiqTokenSent, srcDecimals);
        snapshot.totalLiqTokenReceived = _toLocalDecimals(
            snapshot.totalLiqTokenReceived,
            srcDecimals
        );

        s.parentPool().childPoolSnapshots[sourceChainSelector] = snapshot;
    }

    function _handleConceroReceiveUpdateTargetBalance(bytes calldata) internal pure override {
        revert ICommonErrors.FunctionNotImplemented();
    }
}
