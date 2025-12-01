// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {IBase} from "../interfaces/IBase.sol";

library Storage {
    bytes32 internal constant POOL_BASE =
        keccak256(abi.encode(uint256(keccak256(abi.encodePacked("lanca.base.storage"))) - 1)) &
            ~bytes32(uint256(0xff));

    struct Base {
        uint256 targetBalance;
        uint256 totalLancaFeeInLiqToken;
        mapping(uint32 timestamp => IBase.LiqTokenDailyFlow flow) flowByDay;
        mapping(uint24 chainSelector => bytes32 dstPool) dstPools;
        uint256 totalLiqTokenSent;
        uint256 totalLiqTokenReceived;
        address relayerLib;
        address validatorLib;
        uint8 rebalancerFeeBps;
        uint8 lpFeeBps;
        uint8 lancaBridgeFeeBps;
    }

    /* SLOT-BASED STORAGE ACCESS */
    function base() internal pure returns (Base storage s) {
        bytes32 slot = POOL_BASE;
        assembly {
            s.slot := slot
        }
    }
}
