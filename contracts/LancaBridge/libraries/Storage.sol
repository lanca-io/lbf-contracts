// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

library Namespaces {
    bytes32 internal constant NON_REENTRANT =
        keccak256(
            abi.encode(
                uint256(keccak256(abi.encodePacked("lanca.bridge.nonreentrant.storage"))) - 1
            )
        ) & ~bytes32(uint256(0xff));

    bytes32 internal constant BRIDGE =
        keccak256(abi.encode(uint256(keccak256(abi.encodePacked("lanca.bridge.storage"))) - 1)) &
            ~bytes32(uint256(0xff));
}

library Storage {
    struct Bridge {
        uint256 totalSent;
        uint256 totalReceived;
        mapping(uint24 dstChainSelector => uint256) sentNonces;
        mapping(uint24 srcChainSelector => mapping(uint256 nonce => uint256 tokenAmount)) receivedBridges;
    }

    function bridge() internal pure returns (Bridge storage s) {
        bytes32 slot = Namespaces.BRIDGE;
        assembly {
            s.slot := slot
        }
    }
}
