// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {BridgeCodec} from "../../../contracts/common/libraries/BridgeCodec.sol";
import {ConceroRouterMock} from "../mocks/ConceroRouterMock.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IOUToken} from "../../../contracts/Rebalancer/IOUToken.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {Test} from "forge-std/src/Test.sol";
import {ValidatorCodec} from "@concero/v2-contracts/contracts/common/libraries/ValidatorCodec.sol";
import {StringsUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/StringsUpgradeable.sol";

abstract contract LancaBaseTest is Test {
    using BridgeCodec for bytes32;
    using BridgeCodec for address;
    using BridgeCodec for bytes;

    uint24 public constant PARENT_POOL_CHAIN_SELECTOR = 1000;
    uint24 public constant CHILD_POOL_CHAIN_SELECTOR = 100;
    uint96 public constant AVERAGE_CONCERO_MESSAGE_FEE = 0.1e6;
    uint256 public constant INITIAL_POOL_LIQUIDITY = 1_000_000e6;
    uint256 internal constant MIN_TARGET_BALANCE = 10_000e6;
    uint32 public constant GAS_LIMIT = 100_000;
    bytes32 public constant DEFAULT_MESSAGE_ID = bytes32(uint256(1));
    uint256 public constant NONCE = 1;
    uint8 internal constant USDC_TOKEN_DECIMALS = 6;
    uint8 internal constant STD_TOKEN_DECIMALS = 18;
    uint8 internal constant SCALE_TOKEN_DECIMALS = 24;
    uint8 internal constant REBALANCER_FEE_BPS = 10; // 1bps
    uint8 internal constant LANCA_BRIDGE_FEE_BPS = 50; // 5bps
    uint8 internal constant LP_FEE_BPS = 10; // 1bps
    uint256 internal constant USDC_TOKEN_DECIMALS_SCALE = 10 ** USDC_TOKEN_DECIMALS;
    uint256 internal constant STD_TOKEN_DECIMALS_SCALE = 10 ** STD_TOKEN_DECIMALS;
    uint32 internal constant VALIDATION_GAS_LIMIT = 100_000;
    uint256 internal constant DEFAULT_LIQUIDITY_CAP = 10_000e6;

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
    bytes[] public s_internalValidatorConfigs = new bytes[](1);

    IERC20 public s_usdc = IERC20(new MockERC20("USD Coin", "USDC", USDC_TOKEN_DECIMALS));
    IERC20 public s_18DecUsdc = IERC20(new MockERC20("USD Coin", "USDC", STD_TOKEN_DECIMALS));
    IOUToken public s_iouToken = new IOUToken(s_deployer, address(0), USDC_TOKEN_DECIMALS);
    IOUToken public s_18DecIouToken = new IOUToken(s_deployer, address(0), STD_TOKEN_DECIMALS);

    constructor() {
        s_validationChecks[0] = true;
        s_validatorLibs[0] = s_validatorLib;

        s_internalValidatorConfigs[0] = ValidatorCodec.encodeEvmConfig(VALIDATION_GAS_LIMIT);
    }

    function _constructAccessControlError(
        address account,
        bytes32 role
    ) internal pure returns (bytes memory) {
        return
            abi.encodePacked(
                "AccessControl: account ",
                StringsUpgradeable.toHexString(uint160(account), 20),
                " is missing role ",
                StringsUpgradeable.toHexString(uint256(role), 32)
            );
    }
}
