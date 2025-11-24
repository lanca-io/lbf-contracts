// // SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

library Storage {
    bytes32 internal constant REBALANCER =
        keccak256(
            abi.encode(uint256(keccak256(abi.encodePacked("lanca.rebalancer.storage"))) - 1)
        ) & ~bytes32(uint256(0xff));

    struct Rebalancer {
        uint256 totalRebalancingFeeAmount; // LD
        uint256 totalIouSent;
        uint256 totalIouReceived;
    }

    function rebalancer() internal pure returns (Rebalancer storage r) {
        bytes32 namespace = REBALANCER;
        assembly {
            r.slot := namespace
        }
    }
}
