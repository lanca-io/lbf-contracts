// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {Script} from "forge-std/src/Script.sol";
import {console} from "forge-std/src/Console.sol";

import {ChildPool} from "../../../../contracts/ChildPool/ChildPool.sol";
import {LancaBaseScript} from "../LancaBaseScript.s.sol";

contract DeployChildPool is LancaBaseScript {
    function deployChildPool(
        address liquidityToken,
        uint8 liquidityTokenDecimals,
        uint24 chainSelector,
        address _iouToken,
        address _conceroRouter
    ) public returns (address) {
        vm.startBroadcast(deployer);

        ChildPool pool = new ChildPool(
            _conceroRouter,
            _iouToken,
            liquidityToken,
            liquidityTokenDecimals,
            chainSelector,
            PARENT_POOL_CHAIN_SELECTOR
        );

        console.log("Deployed ChildPool:");
        console.log("  Address:", address(pool));
        console.log("  Liquidity Token:", liquidityToken);
        console.log("  Liquidity Token Decimals:", liquidityTokenDecimals);
        console.log("  Chain Selector:", chainSelector);
        console.log("  IOU Token:", _iouToken);
        console.log("  Concero Router:", _conceroRouter);

        vm.stopBroadcast();

        return address(pool);
    }

    function deployChildPoolForChain(
        address liquidityToken,
        uint24 chainSelector,
        address _iouToken
    ) external returns (address) {
        return
            deployChildPool(
                liquidityToken,
                6, // Default to USDC decimals
                chainSelector,
                _iouToken,
                conceroRouter
            );
    }

    function deployMultipleChildPools(
        address liquidityToken,
        uint24[] memory chainSelectors,
        address[] memory iouTokens
    ) external returns (address[] memory) {
        require(chainSelectors.length == iouTokens.length, "Array length mismatch");

        address[] memory pools = new address[](chainSelectors.length);

        for (uint256 i = 0; i < chainSelectors.length; i++) {
            pools[i] = deployChildPool(
                liquidityToken,
                6, // Default to USDC decimals
                chainSelectors[i],
                iouTokens[i],
                conceroRouter
            );
        }

        return pools;
    }
}
