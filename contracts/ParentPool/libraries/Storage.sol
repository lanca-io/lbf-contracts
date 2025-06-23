import "../interfaces/IParentPool.sol";

library Namespaces {
    bytes32 internal constant PARENT_POOL =
        keccak256(abi.encode(uint256(keccak256(abi.encodePacked("parentPool"))) - 1)) &
            ~bytes32(uint256(0xff));
}

library Storage {
    struct SnapshotSubmission {
        uint256 balance;
        uint32 timestamp;
        // 24 hour inflow, outflow and targetBalance will be added soon
    }

    struct ParentPool {
        mapping(bytes32 id => IParentPool.Deposit deposits) depositsQueue;
        mapping(bytes32 id => IParentPool.Withdraw withdrawals) withdrawalsQueue;
        bytes32[] depositsQueueIds;
        bytes32[] withdrawalsQueueIds;
        uint256 depositNonce;
        uint256 withdrawalNonce;
        uint24[] supportedChainSelectors;
        mapping(uint24 chainSelector => bool isSupported) supportedChainsBySelector;
        mapping(uint24 chainSelector => SnapshotSubmission snapshotSubmition) snapshotSubmissionByChainSelector;
        address lancaKeeper;
    }

    /* SLOT-BASED STORAGE ACCESS */
    function parentPool() internal pure returns (ParentPool storage s) {
        bytes32 slot = Namespaces.PARENT_POOL;
        assembly {
            s.slot := slot
        }
    }
}
