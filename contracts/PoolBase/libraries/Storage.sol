// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {IPoolBase} from "../../PoolBase/interfaces/IPoolBase.sol";

library Namespaces {
    bytes32 internal constant POOL_BASE =
        keccak256(abi.encode(uint256(keccak256(abi.encodePacked("poolBase"))) - 1)) &
            ~bytes32(uint256(0xff));
}

library Storage {
    struct PoolBase {
        uint256 targetBalance;
        uint256 totalLancaFeeInLiqToken;
        mapping(uint32 timestamp => IPoolBase.LiqTokenDailyFlow flow) flowByDay;
        mapping(uint24 chainSelector => address dstPool) dstPools;
    }

    /* SLOT-BASED STORAGE ACCESS */
    function poolBase() internal pure returns (PoolBase storage s) {
        bytes32 slot = Namespaces.POOL_BASE;
        assembly {
            s.slot := slot
        }
    }
}
