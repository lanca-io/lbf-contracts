// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {Script} from "forge-std/src/Script.sol";

import {ConceroRouterMock} from "../../mocks/ConceroRouterMock.sol";

contract DeployMockConceroRouter is Script {
    function deployConceroRouter() public returns (ConceroRouterMock) {
        ConceroRouterMock conceroRouter = new ConceroRouterMock();

        return conceroRouter;
    }
}
