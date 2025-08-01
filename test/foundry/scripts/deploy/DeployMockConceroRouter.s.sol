// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {Script} from "forge-std/src/Script.sol";

import {MockConceroRouter} from "contracts/MockConceroRouter/MockConceroRouter.sol";

contract DeployMockConceroRouter is Script {
    function deployConceroRouter() public returns (MockConceroRouter) {
        MockConceroRouter conceroRouter = new MockConceroRouter();

        return conceroRouter;
    }
}
