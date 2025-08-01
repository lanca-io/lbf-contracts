pragma solidity ^0.8.28;

import {IPoolBase} from "../../PoolBase/interfaces/IPoolBase.sol";
import {IParentPool} from "../interfaces/IParentPool.sol";

library Namespaces {
    bytes32 internal constant PARENT_POOL =
        keccak256(abi.encode(uint256(keccak256(abi.encodePacked("parentPool"))) - 1)) &
            ~bytes32(uint256(0xff));
}

library Storage {
    // @notice all these variables have the scale i_liquidityTokenDecimals
    struct LhsCalculationFactors {
        uint8 lurScoreSensitivity;
        uint8 lurScoreWeight;
        uint8 ndrScoreWeight;
    }

    struct ParentPool {
        mapping(bytes32 id => IParentPool.Deposit deposits) depositsQueue;
        mapping(bytes32 id => IParentPool.Withdrawal withdrawals) withdrawalsQueue;
        uint256 totalDepositAmountInQueue;
        bytes32[] depositsQueueIds;
        bytes32[] withdrawalsQueueIds;
        uint256 depositNonce;
        uint256 withdrawalNonce;
        uint24[] supportedChainSelectors;
        mapping(uint24 dstChainSelector => IParentPool.SnapshotSubmission snapshotSubmition) childPoolsSubmissions;
        mapping(uint24 dstChainSelector => uint256 targetBalance) dstChainsTargetBalances;
        bytes32[] pendingWithdrawalIds;
        mapping(bytes32 id => IParentPool.PendingWithdrawal pendingWithdrawal) pendingWithdrawals;
        LhsCalculationFactors lhsCalculationFactors;
        mapping(uint24 dstChainSelector => address childPool) childPools;
        uint256 totalWithdrawalAmountLocked;
        uint256 remainingWithdrawalAmount;
        uint256 totalLancaFeeInLiqToken;
        address lancaKeeper;
        uint16 targetWithdrawalQueueLength;
        uint16 targetDepositQueueLength;
        uint96 averageConceroMessageFee;
        uint256 minParentPoolTargetBalance;
    }

    /* SLOT-BASED STORAGE ACCESS */
    function parentPool() internal pure returns (ParentPool storage s) {
        bytes32 slot = Namespaces.PARENT_POOL;
        assembly {
            s.slot := slot
        }
    }
}
