// // SPDX-License-Identifier: UNLICENSED
// pragma solidity ^0.8.28;

// library Storage {
//     bytes32 constant REBALANCER_POSITION = keccak256("lanca.rebalancer.storage");

//     struct RebalancerData {
//     }

//     function rebalancerData() internal pure returns (RebalancerData storage rd) {
//         bytes32 position = REBALANCER_POSITION;
//         assembly {
//             rd.slot := position
//         }
//     }
// }
