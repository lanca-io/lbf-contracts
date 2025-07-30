// // SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

library Storage {
    bytes32 constant REBALANCER_NAMESPACE = keccak256("lanca.rebalancer.storage");

    struct Rebalancer {
        mapping(uint24 => address) dstPools;
        uint256 totalRebalancingFee;
    }

    function rebalancer() internal pure returns (Rebalancer storage rd) {
        bytes32 namespace = REBALANCER_NAMESPACE;
        assembly {
            rd.slot := namespace
        }
    }
}
