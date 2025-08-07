pragma solidity ^0.8.28;

import {IPoolBase} from "../../PoolBase/interfaces/IPoolBase.sol";
import {IParentPool} from "../interfaces/IParentPool.sol";

library Namespaces {
    bytes32 internal constant PARENT_POOL =
        keccak256(abi.encode(uint256(keccak256(abi.encodePacked("parentPool"))) - 1)) &
            ~bytes32(uint256(0xff));
}

library Storage {
    struct ParentPool {
        mapping(bytes32 id => IParentPool.Deposit deposits) depositsQueue;
        mapping(bytes32 id => IParentPool.Withdrawal withdrawals) withdrawalsQueue;
        uint256 totalDepositAmountInQueue;
        bytes32[] depositsQueueIds;
        bytes32[] withdrawalsQueueIds;
        uint256 depositNonce;
        uint256 withdrawalNonce;
        mapping(uint24 dstChainSelector => IParentPool.SnapshotSubmission snapshotSubmition) childPoolsSubmissions;
        mapping(uint24 dstChainSelector => uint256 targetBalance) childPoolTargetBalances;
        bytes32[] pendingWithdrawalIds;
        uint24[] supportedChainSelectors;
        mapping(bytes32 id => IParentPool.PendingWithdrawal pendingWithdrawal) pendingWithdrawals;
        uint256 totalWithdrawalAmountLocked;
        uint256 remainingWithdrawalAmount;
        uint256 totalLancaFeeInLiqToken;
        uint256 minParentPoolTargetBalance;
        uint16 targetWithdrawalQueueLength;
        uint16 targetDepositQueueLength;
        uint96 averageConceroMessageFee;
        uint64 lurScoreSensitivity; // has the scale i_liquidityTokenDecimals
        uint64 lurScoreWeight; // has the scale i_liquidityTokenDecimals
        uint64 ndrScoreWeight; // has the scale i_liquidityTokenDecimals
    }

    /* SLOT-BASED STORAGE ACCESS */
    function parentPool() internal pure returns (ParentPool storage s) {
        bytes32 slot = Namespaces.PARENT_POOL;
        assembly {
            s.slot := slot
        }
    }
}
