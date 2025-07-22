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

contract ParentPool is IParentPool, ILancaKeeper, PoolBase {
    using s for s.ParentPool;

    uint32 internal constant UPDATE_TARGET_BALANCE_MESSAGE_GAS_LIMIT = 100_000;

    error SnapshotTimestampNotInRange(uint24 chainSelector, uint32 timestamp);

    modifier onlyLancaKeeper() {
        require(
            msg.sender == s.parentPool().lancaKeeper,
            ICommonErrors.UnauthorizedCaller(msg.sender, s.parentPool().lancaKeeper)
        );

        _;
    }

    constructor(
        address liquidityToken,
        address lpToken,
        address conceroRouter,
        uint8 liquidityTokenDecimals,
        uint24 chainSelector
    ) PoolBase(liquidityToken, lpToken, conceroRouter, liquidityTokenDecimals, chainSelector) {}

    receive() external payable {}

    function enterDepositQueue(uint256 amount) external {
        IERC20(i_liquidityToken).transferFrom(msg.sender, address(this), amount);

        Deposit memory deposit = Deposit({liquidityTokenAmountToDeposit: amount, lp: msg.sender});
        bytes32 depositId = keccak256(
            abi.encodePacked(msg.sender, block.number, ++s.parentPool().depositNonce)
        );

        s.parentPool().depositsQueue[depositId] = deposit;
        s.parentPool().depositsQueueIds.push(depositId);

        emit DepositQueued(depositId, deposit.lp, amount);
    }

    function enterWithdrawQueue(uint256 amount) external {
        IERC20(i_lpToken).transferFrom(msg.sender, address(this), amount);

        Withdrawal memory withdraw = Withdrawal({lpTokenAmountToWithdraw: amount, lp: msg.sender});
        bytes32 withdrawId = keccak256(
            abi.encodePacked(msg.sender, block.number, ++s.parentPool().withdrawalNonce)
        );

        s.parentPool().withdrawalsQueue[withdrawId] = withdraw;
        s.parentPool().withdrawalsQueueIds.push(withdrawId);

        emit WithdrawQueued(withdrawId, withdraw.lp, amount);
    }

    function isReadyForTriggerDepositWithdrawProcess() external view returns (bool) {
        uint24[] memory supportedChainSelectors = s.parentPool().supportedChainSelectors;
        uint256 supportedChainSelectorsLength = supportedChainSelectors.length;

        for (uint256 i; i < supportedChainSelectorsLength; ++i) {
            if (
                !isLiquiditySnapshotTimestampInRange(
                    s
                        .parentPool()
                        .snapshotSubmissionByChainSelector[supportedChainSelectors[i]]
                        .timestamp
                )
            ) {
                return false;
            }
        }

        return true;
    }

    function isLiquiditySnapshotTimestampInRange(uint32 timestamp) public pure returns (bool) {
        // TODO: implement it
        return true;
    }

    function getActiveBalance() public view override returns (uint256) {
        return super.getActiveBalance() - s.parentPool().totalDepositAmountInQueue;
    }

    function triggerDepositWithdrawProcess() external payable onlyLancaKeeper {
        uint256 totalChildPoolsActiveBalance = _getTotalChildPoolsActiveBalance();

        uint256 totalDepositedLiqTokenAmount = _processDepositsQueue(totalChildPoolsActiveBalance);
        uint256 totalLiqTokenAmountToWithdraw = _processWithdrawalsQueue(
            totalChildPoolsActiveBalance
        );

        if (totalDepositedLiqTokenAmount > totalLiqTokenAmountToWithdraw) {
            _updateTargetBalancesWithInflow(
                totalDepositedLiqTokenAmount -
                    totalLiqTokenAmountToWithdraw +
                    totalChildPoolsActiveBalance +
                    getActiveBalance()
            );
        }
    }

    /*   INTERNAL FUNCTIONS   */

    function _getTotalChildPoolsActiveBalance() internal view returns (uint256) {
        uint24[] memory supportedChainSelectors = s.parentPool().supportedChainSelectors;
        uint256 totalChildPoolsBalance;

        for (uint256 i; i < supportedChainSelectors.length; ++i) {
            uint32 snapshotTimestamp = s
                .parentPool()
                .snapshotSubmissionByChainSelector[supportedChainSelectors[i]]
                .timestamp;

            if (!isLiquiditySnapshotTimestampInRange(snapshotTimestamp)) {
                revert SnapshotTimestampNotInRange(supportedChainSelectors[i], snapshotTimestamp);
            }

            totalChildPoolsBalance += s
                .parentPool()
                .snapshotSubmissionByChainSelector[supportedChainSelectors[i]]
                .balance;
        }

        return totalChildPoolsBalance;
    }

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

    function _updateTargetBalancesWithInflow(uint256 totalLbfBalance) internal {
        (
            uint24[] memory chainSelectors,
            uint256[] memory targetBalances
        ) = _calculateNewTargetBalances(totalLbfBalance);

        for (uint256 i; i < chainSelectors.length; ++i) {
            if (chainSelectors[i] != i_chainSelector) {
                _updateChainTargetBalance(chainSelectors[i], targetBalances[i]);
            } else {
                _setTargetBalance(targetBalances[i]);
            }
        }
    }

    function _calculateLpTokenAmountToMint(
        uint256 totalLbfActiveBalance,
        uint256 liquidityTokenAmountToDeposit
    ) internal returns (uint256) {
        uint256 totalSupply = IERC20(i_lpToken).totalSupply();

        if (totalSupply == 0) {
            return toLpTokenDecimals(liquidityTokenAmountToDeposit);
        }

        uint256 totalLbfActiveBalanceConverted = toLpTokenDecimals(totalLbfActiveBalance);
        uint256 liquidityTokenAmountToDepositConverted = toLpTokenDecimals(
            liquidityTokenAmountToDeposit
        );

        return
            (totalSupply * liquidityTokenAmountToDepositConverted) / totalLbfActiveBalanceConverted;
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
    ) internal returns (uint24[] memory, uint256[] memory) {
        uint24[] memory childPoolChainSelectors = getSupportedChainSelectors();
        uint24[] memory chainSelectors = new uint24[](childPoolChainSelectors.length + 1);
        uint256[] memory weights = new uint256[](chainSelectors.length);
        LiqTokenAmountFlow memory flow;
        uint256 tagetBalance;
        uint256 targetBalancesSum;

        chainSelectors[chainSelectors.length - 1] = getChainSelector();

        for (uint256 i; i < childPoolChainSelectors.length; ++i) {
            chainSelectors[i] = childPoolChainSelectors[i];
            flow = s
                .parentPool()
                .snapshotSubmissionByChainSelector[childPoolChainSelectors[i]]
                .flow;

            tagetBalance = s.parentPool().dstChainsTargetBalances[childPoolChainSelectors[i]];
            targetBalancesSum += tagetBalance;

            weights[i] = tagetBalance * _calculateLhsScore(flow, tagetBalance);
        }

        weights[weights.length - 1] = _calculateParentPoolTargetBalanceWeight();

        uint256 totalWeight;

        for (uint256 i; i < weights.length; ++i) {
            totalWeight += weights[i];
        }

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

    function _calculateLurScore(
        uint256 inflow,
        uint256 outflow,
        uint256 balance
    ) internal view returns (uint8) {
        uint256 lur = (inflow + outflow) / balance;

        return uint8(1 - (lur / (s.parentPool().lhsCalculationFactors.lurScoreSensitivity + lur)));
    }

    function _calculateNdrScore(
        uint256 inflow,
        uint256 outflow,
        uint256 balance
    ) internal pure returns (uint8) {
        // TODO: double check if (targetBalance == 0) condition needed
        if (inflow >= outflow || balance == 0) return 1;

        uint256 ndr = (outflow - inflow) / balance;
        return uint8(1 - ndr);
    }

    function _calculateLhsScore(
        LiqTokenAmountFlow memory flow,
        uint256 tagetBalance
    ) internal returns (uint8) {
        uint8 lurScore = _calculateLurScore(flow.inflow, flow.outflow, tagetBalance);
        uint8 ndrScore = _calculateNdrScore(flow.inflow, flow.outflow, tagetBalance);

        uint8 lhs = (s.parentPool().lhsCalculationFactors.lurScoreWeight * lurScore) +
            (s.parentPool().lhsCalculationFactors.ndrScoreWeight * ndrScore);

        return 1 + (1 - lhs);
    }

    function _calculateTargetBalance(
        uint256 weight,
        uint256 totalWeight,
        uint256 totalLbfBalance
    ) internal returns (uint256) {
        return (weight / totalWeight) * totalLbfBalance;
    }

    function _calculateParentPoolTargetBalanceWeight() internal returns (uint256) {
        uint256 targetBalance = getTargetBalance();
        return targetBalance * _calculateLhsScore(getYesterdayFlow(), targetBalance);
    }

    function _updateChainTargetBalance(uint24 dstChainSelector, uint256 newTargetBalance) internal {
        s.parentPool().dstChainsTargetBalances[dstChainSelector] = newTargetBalance;

        address childPool = s.parentPool().childPools[dstChainSelector];
        require(childPool != address(0), ICommonErrors.InvalidDstChainSelector(dstChainSelector));

        ConceroTypes.EvmDstChainData memory dstChainData = ConceroTypes.EvmDstChainData({
            gasLimit: UPDATE_TARGET_BALANCE_MESSAGE_GAS_LIMIT,
            receiver: childPool
        });

        address conceroRouter = getConceroRouter();

        uint256 messageFee = IConceroRouter(conceroRouter).getMessageFee(
            dstChainSelector,
            false,
            address(0),
            dstChainData
        );

        bytes memory messagePayload = abi.encode(
            ConceroMessageType.UPDATE_TARGET_BALANCE,
            newTargetBalance
        );

        IConceroRouter(conceroRouter).conceroSend{value: messageFee}(
            dstChainSelector,
            false,
            address(0),
            dstChainData,
            messagePayload
        );
    }
}
