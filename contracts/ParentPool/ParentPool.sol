// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {ICommonErrors} from "../common/interfaces/ICommonErrors.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ILancaKeeper} from "./interfaces/ILancaKeeper.sol";
import {IParentPool} from "./interfaces/IParentPool.sol";
import {PoolBase} from "../PoolBase/PoolBase.sol";
import {Storage as s} from "./libraries/Storage.sol";
import {LPToken} from "./LPToken.sol";

contract ParentPool is IParentPool, ILancaKeeper, PoolBase {
    using s for s.ParentPool;

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
        uint8 liquidityTokenDecimals
    ) PoolBase(liquidityToken, lpToken, liquidityTokenDecimals) {}

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

    function triggerDepositWithdrawProcess() external onlyLancaKeeper {
        uint256 totalChildPoolsActiveBalance = _getTotalChildPoolsActiveBalance();

        _handleDepositsQueue(totalChildPoolsActiveBalance);
        _handleWithdrawalsQueue(totalChildPoolsActiveBalance);

        // TODO: update all target balances on all chains (including local)
    }

    /*   INTERNAL FUNCTIONS   */

    function _getTotalChildPoolsActiveBalance() internal view returns (uint256) {
        uint24[] memory supportedChainSelectors = s.parentPool().supportedChainSelectors;
        uint256 supportedChainSelectorsLength = supportedChainSelectors.length;

        uint256 totalLbfActiveBalance;

        for (uint256 i; i < supportedChainSelectorsLength; ++i) {
            uint32 snapshotTimestamp = s
                .parentPool()
                .snapshotSubmissionByChainSelector[supportedChainSelectors[i]]
                .timestamp;

            if (!isLiquiditySnapshotTimestampInRange(snapshotTimestamp)) {
                revert SnapshotTimestampNotInRange(supportedChainSelectors[i], snapshotTimestamp);
            }

            totalLbfActiveBalance += s
                .parentPool()
                .snapshotSubmissionByChainSelector[supportedChainSelectors[i]]
                .balance;
        }

        return totalLbfActiveBalance;
    }

    function _handleDepositsQueue(uint256 totalChildPoolsActiveBalance) internal {
        bytes32[] memory depositsQueueIds = s.parentPool().depositsQueueIds;

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
        }

        delete s.parentPool().depositsQueueIds;

        // TODO: return info for updating target balances on all chains
    }

    function _handleWithdrawalsQueue(uint256 totalChildPoolsActiveBalance) internal {
        bytes32[] memory withdrawalsQueueIds = s.parentPool().withdrawalsQueueIds;

        uint256 totalLiqTokenAmountToWithdraw;

        for (uint256 i; i < withdrawalsQueueIds.length; ++i) {
            totalLiqTokenAmountToWithdraw += _calculateWithdrawableAmount(
                totalChildPoolsActiveBalance,
                s.parentPool().withdrawalsQueue[withdrawalsQueueIds[i]].lpTokenAmountToWithdraw
            );
        }

        _setTargetBalance(getTargetBalance() + totalLiqTokenAmountToWithdraw);

        // TODO: return info for updating target balances on all chains
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
}
