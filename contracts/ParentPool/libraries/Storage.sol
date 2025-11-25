// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {IParentPool} from "../interfaces/IParentPool.sol";

library Namespaces {
    bytes32 internal constant PARENT_POOL =
        keccak256(abi.encode(uint256(keccak256(abi.encodePacked("parentPool"))) - 1)) &
            ~bytes32(uint256(0xff));
}

library Storage {
    struct ParentPool {
        mapping(bytes32 id => IParentPool.Deposit deposits) depositQueue;
        mapping(bytes32 id => IParentPool.Withdrawal withdrawals) withdrawalQueue;
        uint256 totalDepositAmountInQueue;
        bytes32[] depositQueueIds;
        bytes32[] withdrawalQueueIds;
        uint256 depositNonce;
        uint256 withdrawalNonce;
        mapping(uint24 dstChainSelector => IParentPool.ChildPoolSnapshot snapshot) childPoolSnapshots;
        mapping(uint24 dstChainSelector => uint256 targetBalance) childPoolTargetBalances;
        bytes32[] pendingWithdrawalIds;
        uint24[] supportedChainSelectors;
        mapping(bytes32 id => IParentPool.PendingWithdrawal pendingWithdrawal) pendingWithdrawals;
        uint256 totalWithdrawalAmountLocked;
        uint256 remainingWithdrawalAmount;
        uint256 DEPRECATED_totalLancaFeeInLiqToken;
        uint256 targetBalanceFloor;
        uint256 prevTotalPoolsBalance;
        uint256 liquidityCap;
        uint16 minWithdrawalQueueLength;
        uint16 minDepositQueueLength;
        uint96 averageConceroMessageFee;
        uint64 lurScoreSensitivity; // has the scale i_liquidityTokenDecimals
        uint64 lurScoreWeight; // has the scale i_liquidityTokenDecimals
        uint64 ndrScoreWeight; // has the scale i_liquidityTokenDecimals
        uint64 minDepositAmount;
        uint64 minWithdrawalAmount;
    }

    /* SLOT-BASED STORAGE ACCESS */
    function parentPool() internal pure returns (ParentPool storage s) {
        bytes32 slot = Namespaces.PARENT_POOL;
        assembly {
            s.slot := slot
        }
    }
}
