// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Script} from "forge-std/src/Script.sol";
import {ConceroRouterMock} from "../mocks/ConceroRouterMock.sol";

import {DeployMockConceroRouter} from "../scripts/deploy/DeployMockConceroRouter.s.sol";

abstract contract LancaBaseScript is Script {
    address public immutable deployer;
    address public immutable proxyDeployer;

    IERC20 public usdc;
    address public iouToken;
    address public conceroRouter;
    address public s_lancaKeeper;

    address public constant operator = address(0x4242424242424242424242424242424242424242);
    address public constant user = address(0x0101010101010101010101010101010101010101);
    address public constant liquidityProvider = address(0x0202020202020202020202020202020202020202);

    uint24 public constant PARENT_POOL_CHAIN_SELECTOR = 1000;
    uint24 public constant CHILD_POOL_CHAIN_SELECTOR = 100;
    uint256 public constant INITIAL_POOL_LIQUIDITY = 1_000_000e6;
    uint256 internal constant MIN_TARGET_BALANCE = 10_000e6;

    uint256 public constant GAS_LIMIT = 100_000;
	bytes32 public constant DEFAULT_MESSAGE_ID = bytes32(uint256(1));

    constructor() {
        deployer = vm.envAddress("DEPLOYER_ADDRESS");
        proxyDeployer = vm.envAddress("PROXY_DEPLOYER_ADDRESS");
        conceroRouter = address(new ConceroRouterMock());
        s_lancaKeeper = makeAddr("lbfKeeper");
    }
}
