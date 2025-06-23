import "../interfaces/IParentPool.sol";

library Namespaces {
    bytes32 internal constant PARENT_POOL =
        keccak256(abi.encode(uint256(keccak256(abi.encodePacked("parentPool"))) - 1)) &
            ~bytes32(uint256(0xff));
}

library Storage {
    struct ParentPool {
        mapping(bytes32 id => IParentPool.Deposit deposits) depositsQueue;
        mapping(bytes32 id => IParentPool.Withdraw withdrawals) withdrawalsQueue;
        bytes32[] depositsQueueIds;
        bytes32[] withdrawalsQueueIds;
        uint256 depositNonce;
        uint256 withdrawalNonce;
    }

    /* SLOT-BASED STORAGE ACCESS */
    function parentPool() internal pure returns (ParentPool storage s) {
        bytes32 slot = Namespaces.PARENT_POOL;
        assembly {
            s.slot := slot
        }
    }
}
