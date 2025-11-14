// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {IBase} from "../interfaces/IBase.sol";

library Namespaces {
    bytes32 internal constant POOL_BASE =
        keccak256(abi.encode(uint256(keccak256(abi.encodePacked("lanca.base.storage"))) - 1)) &
            ~bytes32(uint256(0xff));
}

library Storage {
    struct Base {
        uint256 targetBalance;
        uint256 totalLancaFeeInLiqToken;
        address lancaKeeper;
        mapping(uint32 timestamp => IBase.LiqTokenDailyFlow flow) flowByDay;
        mapping(uint24 chainSelector => address dstPool) dstPools;
        uint256 totalLiqTokenSent;
        uint256 totalLiqTokenReceived;
        mapping(uint24 dstChainSelector => address relayerLib) relayerLibs;
        mapping(uint24 dstChainSelector => address[] validatorLibs) validatorLibs;
    }

    /* SLOT-BASED STORAGE ACCESS */
    function base() internal pure returns (Base storage s) {
        bytes32 slot = Namespaces.POOL_BASE;
        assembly {
            s.slot := slot
        }
    }
}
