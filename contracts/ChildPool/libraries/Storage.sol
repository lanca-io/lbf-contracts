// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

library Namespaces {
    bytes32 internal constant CHILD_POOL =
        keccak256(abi.encode(uint256(keccak256(abi.encodePacked("lanca.childPool.storage"))) - 1)) &
            ~bytes32(uint256(0xff));
}

library Storage {
    struct ChildPool {
        address lancaKeeper;
    }

    function childPool() internal pure returns (ChildPool storage s) {
        bytes32 slot = Namespaces.CHILD_POOL;
        assembly {
            s.slot := slot
        }
    }
}
