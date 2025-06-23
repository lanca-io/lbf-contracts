// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {ICommonErrors} from "../common/interfaces/ICommonErrors.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ILancaKeeper} from "./interfaces/ILancaKeeper.sol";
import {IParentPool} from "./interfaces/IParentPool.sol";
import {PoolBase} from "../PoolBase/PoolBase.sol";
import {Storage as s} from "./libraries/Storage.sol";

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

    constructor(address liquidityToken, address lpToken) PoolBase(liquidityToken, lpToken) {}

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

        Withdraw memory withdraw = Withdraw({lpTokenAmountToWithdraw: amount, lp: msg.sender});
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
                !isTimestampInRange(
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

    function isTimestampInRange(uint32 timestamp) public pure returns (bool) {
        // TODO: implement it
        return true;
    }

    function triggerDepositWithdrawProcess() external onlyLancaKeeper {
        uint256 totalLbfActiveBalance = _getTotalLbfActiveBalance();
    }

    /*   INTERNAL FUNCTIONS   */

    function _getTotalLbfActiveBalance() internal view returns (uint256) {
        uint24[] memory supportedChainSelectors = s.parentPool().supportedChainSelectors;
        uint256 supportedChainSelectorsLength = supportedChainSelectors.length;

        uint256 totalLbfActiveBalance = getActiveBalance();

        for (uint256 i; i < supportedChainSelectorsLength; ++i) {
            uint32 snapshotTimestamp = s
                .parentPool()
                .snapshotSubmissionByChainSelector[supportedChainSelectors[i]]
                .timestamp;

            if (!isTimestampInRange(snapshotTimestamp)) {
                revert SnapshotTimestampNotInRange(supportedChainSelectors[i], snapshotTimestamp);
            }

            totalLbfActiveBalance += s
                .parentPool()
                .snapshotSubmissionByChainSelector[supportedChainSelectors[i]]
                .balance;
        }

        return totalLbfActiveBalance;
    }
}
