// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {ParentPoolHarness} from "../../harnesses/ParentPoolHarness.sol";
import {LancaBaseScript} from "../LancaBaseScript.s.sol";

import {ParentPool} from "../../../../contracts/ParentPool/ParentPool.sol";
import {Script} from "forge-std/src/Script.sol";
import {console} from "forge-std/src/Console.sol";

contract DeployParentPool is LancaBaseScript {
    function deployParentPool(
        address liquidityToken,
        uint8 liquidityTokenDecimals,
        address _lpToken,
        address _conceroRouter,
        uint24 chainSelector,
        address _iouToken
    ) public returns (address) {
        vm.startBroadcast(deployer);

        ParentPoolHarness pool = new ParentPoolHarness(
            liquidityToken,
            liquidityTokenDecimals,
            _lpToken,
            _conceroRouter,
            chainSelector,
            _iouToken
        );

        console.log("Deployed ParentPool:");
        console.log("  Address:", address(pool));
        console.log("  Liquidity Token:", liquidityToken);
        console.log("  Liquidity Token Decimals:", liquidityTokenDecimals);
        console.log("  LP Token:", _lpToken);
        console.log("  Concero Router:", _conceroRouter);
        console.log("  Chain Selector:", chainSelector);
        console.log("  IOU Token:", _iouToken);

        vm.stopBroadcast();

        return address(pool);
    }

    function deployParentPoolWithDefaults(
        address liquidityToken,
        address _lpToken,
        address _iouToken
    ) external returns (address) {
        return
            deployParentPool(
                liquidityToken,
                6, // Default to USDC decimals
                _lpToken,
                conceroRouter,
                PARENT_POOL_CHAIN_SELECTOR,
                _iouToken
            );
    }
}
