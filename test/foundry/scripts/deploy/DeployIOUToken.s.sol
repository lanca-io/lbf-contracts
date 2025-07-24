// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {Script} from "forge-std/src/Script.sol";
import {console} from "forge-std/src/Console.sol";

import {IOUToken} from "../../../../contracts/Rebalancer/IOUToken.sol";
import {LancaBaseScript} from "../LancaBaseScript.s.sol";

contract DeployIOUToken is LancaBaseScript {
    function deployIOUToken(address admin, address pool) public returns (address) {
        vm.startBroadcast(deployer);

        IOUToken token = new IOUToken(admin, pool);

        console.log("Deployed IOUToken:");
        console.log("  Address:", address(token));
        console.log("  Admin:", admin);
        console.log("  Pool:", pool);

        vm.stopBroadcast();

        return address(token);
    }

    function deployIOUTokenWithPool(address pool) external returns (address) {
        return deployIOUToken(deployer, pool);
    }
}
