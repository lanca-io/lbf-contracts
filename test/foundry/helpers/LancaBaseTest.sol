// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {BridgeCodec} from "../../../contracts/common/libraries/BridgeCodec.sol";
import {ConceroRouterMock} from "../mocks/ConceroRouterMock.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IOUToken} from "../../../contracts/Rebalancer/IOUToken.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {Test} from "forge-std/src/Test.sol";

abstract contract LancaBaseTest is Test {
    using BridgeCodec for bytes32;
    using BridgeCodec for address;
    using BridgeCodec for bytes;

    uint24 public constant PARENT_POOL_CHAIN_SELECTOR = 1000;
    uint24 public constant CHILD_POOL_CHAIN_SELECTOR = 100;
    uint256 public constant INITIAL_POOL_LIQUIDITY = 1_000_000e6;
    uint256 internal constant MIN_TARGET_BALANCE = 10_000e6;
    uint256 internal constant LIQ_TOKEN_SCALE_FACTOR = 1e6;
    uint32 public constant GAS_LIMIT = 100_000;
    bytes32 public constant DEFAULT_MESSAGE_ID = bytes32(uint256(1));
    uint256 public constant NONCE = 1;
    uint8 internal constant USDC_TOKEN_DECIMALS = 6;

    address public s_deployer = vm.envAddress("DEPLOYER_ADDRESS");
    address public s_proxyDeployer = vm.envAddress("PROXY_DEPLOYER_ADDRESS");
    address public s_conceroRouter = address(new ConceroRouterMock());
    address public s_lancaKeeper = makeAddr("lancaKeeper");
    address public s_relayerLib = makeAddr("relayerLib");
    address public s_validatorLib = makeAddr("validatorLib");
    address public s_mockParentPool = makeAddr("parentPool");
    address public s_mockChildPool = makeAddr("childPool");
    address public s_user = makeAddr("user");
    address public s_operator = makeAddr("operator");
    address public s_liquidityProvider = makeAddr("liquidityProvider");
    bool[] public s_validationChecks = new bool[](1);
    address[] public s_validatorLibs = new address[](1);
    IERC20 public s_usdc = IERC20(new MockERC20("USD Coin", "USDC", USDC_TOKEN_DECIMALS));
    IOUToken public s_iouToken = IOUToken(new IOUToken(s_deployer, address(0)));

    constructor() {
        s_validationChecks[0] = true;
        s_validatorLibs[0] = s_validatorLib;
    }
}
