// // SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

library Namespaces {
    bytes32 internal constant REBALANCER =
        keccak256(
            abi.encode(uint256(keccak256(abi.encodePacked("lanca.rebalancer.storage"))) - 1)
        ) & ~bytes32(uint256(0xff));
}

library Storage {
    struct Rebalancer {
        uint256 totalRebalancingFee;
        uint256 totalIouSent;
        uint256 totalIouReceived;
    }

    function rebalancer() internal pure returns (Rebalancer storage rd) {
        bytes32 namespace = Namespaces.REBALANCER;
        assembly {
            rd.slot := namespace
        }
    }
}
