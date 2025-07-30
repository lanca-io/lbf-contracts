// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {Script} from "forge-std/src/Script.sol";
import {console} from "forge-std/src/Console.sol";

import {LPToken} from "../../../../contracts/ParentPool/LPToken.sol";
import {LancaBaseScript} from "../LancaBaseScript.s.sol";

contract DeployLPToken is LancaBaseScript {
    function deployLPToken(address defaultAdmin, address minter) public returns (address) {
        vm.startBroadcast(deployer);

        LPToken token = new LPToken(defaultAdmin, minter);

        console.log("Deployed LPToken:");
        console.log("  Address:", address(token));
        console.log("  Default Admin:", defaultAdmin);
        console.log("  Minter:", minter);

        vm.stopBroadcast();

        return address(token);
    }

    function deployLPTokenWithMinter(address minter) external returns (address) {
        return deployLPToken(deployer, minter);
    }
}
