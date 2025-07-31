// // SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

library Storage {
    // TODO: replace with keccak256(abi.encode(uint256(keccak256(abi.encodePacked("poolBase"))) - 1)) &
    //            ~bytes32(uint256(0xff));
    bytes32 constant REBALANCER_NAMESPACE = keccak256("lanca.rebalancer.storage");

    struct Rebalancer {
        mapping(uint24 => address) dstPools;
        uint256 totalRebalancingFee;
        uint256 totalIouSent;
        uint256 totalIouReceived;
    }

    function rebalancer() internal pure returns (Rebalancer storage rd) {
        bytes32 namespace = REBALANCER_NAMESPACE;
        assembly {
            rd.slot := namespace
        }
    }
}
