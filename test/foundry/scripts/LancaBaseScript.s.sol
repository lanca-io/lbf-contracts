// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {Test} from "forge-std/src/Test.sol";

import {IOUToken} from "../../../contracts/Rebalancer/IOUToken.sol";
import {ConceroRouterMock} from "../mocks/ConceroRouterMock.sol";
import {DeployMockConceroRouter} from "../scripts/deploy/DeployMockConceroRouter.s.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

abstract contract LancaBaseScript is Test {
    address public immutable deployer;
    address public immutable proxyDeployer;

    IERC20 public usdc;
    IOUToken public iouToken;
    address public conceroRouter;

    address public s_lancaKeeper = makeAddr("lancaKeeper");
    address public relayerLib = makeAddr("relayerLib");
    address public validatorLib = makeAddr("validatorLib");
    address public mockParentPool = makeAddr("parentPool");
    address public mockChildPool = makeAddr("childPool");
    address public user = makeAddr("user");
    address public operator = makeAddr("operator");
    address public liquidityProvider = makeAddr("liquidityProvider");

    uint24 public constant PARENT_POOL_CHAIN_SELECTOR = 1000;
    uint24 public constant CHILD_POOL_CHAIN_SELECTOR = 100;
    uint256 public constant INITIAL_POOL_LIQUIDITY = 1_000_000e6;
    uint256 internal constant MIN_TARGET_BALANCE = 10_000e6;
    uint256 internal constant LIQ_TOKEN_SCALE_FACTOR = 1e6;

    uint256 public constant GAS_LIMIT = 100_000;
    bytes32 public constant DEFAULT_MESSAGE_ID = bytes32(uint256(1));
    uint256 public constant NONCE = 1;

    bool[] public validationChecks = new bool[](1);
    address[] public validatorLibs = new address[](1);

    constructor() {
        deployer = vm.envAddress("DEPLOYER_ADDRESS");
        proxyDeployer = vm.envAddress("PROXY_DEPLOYER_ADDRESS");
        conceroRouter = address(new ConceroRouterMock());

        validationChecks[0] = true;
        validatorLibs[0] = validatorLib;
    }
}
