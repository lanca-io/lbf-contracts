// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

library Namespaces {
    bytes32 internal constant NON_REENTRANT =
        keccak256(
            abi.encode(uint256(keccak256(abi.encodePacked("lancabridge.nonreentrant.storage"))) - 1)
        ) & ~bytes32(uint256(0xff));
}

library Storage {
    struct NonReentrant {
        uint256 status;
    }

    function nonReentrant() internal pure returns (NonReentrant storage s) {
        bytes32 slot = Namespaces.NON_REENTRANT;
        assembly {
            s.slot := slot
        }
    }
}
