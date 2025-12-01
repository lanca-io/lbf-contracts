// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {ICommonErrors} from "../common/interfaces/ICommonErrors.sol";
import {ConceroClient} from "@concero/v2-contracts/contracts/ConceroClient/ConceroClient.sol";
import {MessageCodec} from "@concero/v2-contracts/contracts/common/libraries/MessageCodec.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IOUToken} from "../Rebalancer/IOUToken.sol";
import {IBase} from "./interfaces/IBase.sol";
import {Storage as rs} from "../Rebalancer/libraries/Storage.sol";
import {Storage as s} from "./libraries/Storage.sol";
import {BridgeCodec} from "../common/libraries/BridgeCodec.sol";
import {Decimals} from "../common/libraries/Decimals.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";

abstract contract Base is IBase, AccessControlUpgradeable, ConceroClient {
    using s for s.Base;
    using rs for rs.Rebalancer;
    using MessageCodec for bytes;
    using BridgeCodec for bytes32;
    using BridgeCodec for bytes;
    using Decimals for uint256;

    error ValidatorAlreadySet(address currentValidator);
    error RelayerAlreadySet(address currentRelayer);
    error ValidatorIsNotSet();
    error RelayerIsNotSet();
    error InvalidLiqTokenDecimals();

    uint24 internal constant BPS_DENOMINATOR = 100_000;
    uint32 private constant SECONDS_IN_DAY = 86400;
    bytes32 public constant ADMIN = keccak256("ADMIN");
    bytes32 public constant LANCA_KEEPER = keccak256("LANCA_KEEPER");

    uint24 internal immutable i_chainSelector;
    address internal immutable i_liquidityToken;
    IOUToken internal immutable i_iouToken;
    uint8 internal immutable i_liquidityTokenDecimals;

    constructor(
        address liquidityToken,
        address conceroRouter,
        address iouToken,
        uint24 chainSelector
    ) AccessControlUpgradeable() ConceroClient(conceroRouter) {
        i_liquidityTokenDecimals = IERC20Metadata(liquidityToken).decimals();
        i_iouToken = IOUToken(iouToken);

        require(i_iouToken.decimals() == i_liquidityTokenDecimals, InvalidLiqTokenDecimals());

        i_liquidityToken = liquidityToken;
        i_chainSelector = chainSelector;
    }

    receive() external payable {}

    // INITIALIZER //

    function initialize(address admin, address lancaKeeper) public initializer {
        _setRoleAdmin(LANCA_KEEPER, ADMIN);

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(ADMIN, admin);
        _grantRole(LANCA_KEEPER, lancaKeeper);
    }

    /*   VIEW FUNCTIONS   */

    function getActiveBalance() public view virtual returns (uint256) {
        return
            IERC20(i_liquidityToken).balanceOf(address(this)) -
            s.base().totalLancaFeeInLiqToken -
            rs.rebalancer().totalRebalancingFeeAmount;
    }

    function getSurplus() public view returns (uint256) {
        uint256 activeBalance = getActiveBalance();
        uint256 targetBalance = getTargetBalance();

        if (activeBalance <= targetBalance) return 0;
        return activeBalance - targetBalance;
    }

    function getDeficit() public view returns (uint256 deficit) {
        uint256 targetBalance = getTargetBalance();
        uint256 activeBalance = getActiveBalance();
        deficit = activeBalance >= targetBalance ? 0 : targetBalance - activeBalance;
    }

    function getPoolData() external view returns (uint256 deficit, uint256 surplus) {
        deficit = getDeficit();
        surplus = getSurplus();
    }

    function getDstPool(uint24 chainSelector) public view returns (bytes32) {
        return s.base().dstPools[chainSelector];
    }

    function getRelayerLib() public view returns (address) {
        return s.base().relayerLib;
    }

    function getValidatorLib() public view returns (address) {
        return s.base().validatorLib;
    }

    function getLiquidityToken() public view returns (address) {
        return i_liquidityToken;
    }

    function getTargetBalance() public view returns (uint256) {
        return s.base().targetBalance;
    }

    function getYesterdayFlow() public view returns (LiqTokenDailyFlow memory) {
        return s.base().flowByDay[getYesterdayStartTimestamp()];
    }

    function getTodayStartTimestamp() public view returns (uint32) {
        return uint32(block.timestamp) / SECONDS_IN_DAY;
    }

    function getYesterdayStartTimestamp() public view returns (uint32) {
        return getTodayStartTimestamp() - 1;
    }

    function getLpFee(uint256 amount) public view returns (uint256) {
        return (amount * s.base().lpFeeBps) / BPS_DENOMINATOR;
    }

    function getLancaFee(uint256 amount) public view returns (uint256) {
        return (amount * (s.base().lancaBridgeFeeBps)) / BPS_DENOMINATOR;
    }

    function getRebalancerFee(uint256 amount) public view returns (uint256) {
        return (amount * s.base().rebalancerFeeBps) / BPS_DENOMINATOR;
    }

    function getRebalancerFeeBps() external view returns (uint8) {
        return s.base().rebalancerFeeBps;
    }

    function getLpFeeBps() external view returns (uint8) {
        return s.base().lpFeeBps;
    }

    function getLancaBridgeFeeBps() external view returns (uint8) {
        return s.base().lancaBridgeFeeBps;
    }

    /*   ADMIN FUNCTIONS   */

    function setDstPool(uint24 chainSelector, bytes32 dstPool) public virtual onlyRole(ADMIN) {
        require(chainSelector != i_chainSelector, ICommonErrors.InvalidChainSelector());
        require(dstPool != bytes32(0), ICommonErrors.AddressShouldNotBeZero());

        s.base().dstPools[chainSelector] = dstPool;
    }

    function setRelayerLib(address relayerLib) external onlyRole(ADMIN) {
        s.Base storage s_base = s.base();

        require(relayerLib != address(0), ICommonErrors.AddressShouldNotBeZero());
        require(s_base.relayerLib == address(0), RelayerAlreadySet(s_base.relayerLib));

        s_base.relayerLib = relayerLib;
        _setIsRelayerLibAllowed(relayerLib, true);
    }

    function removeRelayerLib() external onlyRole(ADMIN) {
        s.Base storage s_base = s.base();

        address currentRelayer = s_base.relayerLib;
        require(currentRelayer != address(0), RelayerIsNotSet());

        _setIsRelayerLibAllowed(currentRelayer, false);

        s_base.relayerLib = address(0);
    }

    function setValidatorLib(address validatorLib) external onlyRole(ADMIN) {
        s.Base storage s_base = s.base();

        require(validatorLib != address(0), ICommonErrors.AddressShouldNotBeZero());
        require(s_base.validatorLib == address(0), ValidatorAlreadySet(s_base.validatorLib));

        s_base.validatorLib = validatorLib;

        _setRequiredValidatorsCount(1);
        _setIsValidatorAllowed(validatorLib, true);
    }

    function removeValidatorLib() external onlyRole(ADMIN) {
        s.Base storage s_base = s.base();

        address currentValidator = s_base.validatorLib;
        require(currentValidator != address(0), ValidatorIsNotSet());

        _setRequiredValidatorsCount(0);
        _setIsValidatorAllowed(currentValidator, false);

        s_base.validatorLib = address(0);
    }

    function setRebalancerFeeBps(uint8 rebalancerFeeBps) external onlyRole(ADMIN) {
        s.base().rebalancerFeeBps = rebalancerFeeBps;
    }

    function setLpFeeBps(uint8 lpFeeBps) external onlyRole(ADMIN) {
        s.base().lpFeeBps = lpFeeBps;
    }

    function setLancaBridgeFeeBps(uint8 lancaBridgeFeeBps) external onlyRole(ADMIN) {
        s.base().lancaBridgeFeeBps = lancaBridgeFeeBps;
    }

    /*   INTERNAL FUNCTIONS   */

    function _toLocalDecimals(
        uint256 amountInSrcDecimals,
        uint8 srcDecimals
    ) internal view returns (uint256) {
        return amountInSrcDecimals.toDecimals(srcDecimals, i_liquidityTokenDecimals);
    }

    function _conceroReceive(bytes calldata messageReceipt) internal override {
        s.Base storage s_base = s.base();

        (address sender, ) = messageReceipt.evmSrcChainData();
        uint24 sourceChainSelector = messageReceipt.srcChainSelector();

        require(
            s_base.dstPools[sourceChainSelector].toAddress() == sender,
            ICommonErrors.UnauthorizedSender(
                sender,
                s_base.dstPools[sourceChainSelector].toAddress()
            )
        );

        bytes calldata message = messageReceipt.calldataPayload();
        bytes32 messageId = keccak256(messageReceipt);
        ConceroMessageType messageType = message.getMessageType();

        if (messageType == ConceroMessageType.BRIDGE_IOU) {
            _handleConceroReceiveBridgeIou(messageId, sourceChainSelector, message);
        } else if (messageType == ConceroMessageType.SEND_SNAPSHOT) {
            _handleConceroReceiveSnapshot(sourceChainSelector, message);
        } else if (messageType == ConceroMessageType.BRIDGE) {
            _handleConceroReceiveBridgeLiquidity(
                messageId,
                sourceChainSelector,
                messageReceipt.nonce(),
                message
            );
        } else if (messageType == ConceroMessageType.UPDATE_TARGET_BALANCE) {
            _handleConceroReceiveUpdateTargetBalance(message);
        } else {
            revert InvalidConceroMessageType();
        }
    }

    function _handleConceroReceiveBridgeIou(
        bytes32 messageId,
        uint24 sourceChainSelector,
        bytes calldata messageData
    ) internal virtual;

    function _handleConceroReceiveSnapshot(
        uint24 sourceChainSelector,
        bytes calldata messageData
    ) internal virtual;

    function _handleConceroReceiveBridgeLiquidity(
        bytes32 messageId,
        uint24 sourceChainSelector,
        uint256 nonce,
        bytes calldata messageData
    ) internal virtual;

    function _handleConceroReceiveUpdateTargetBalance(bytes calldata messageData) internal virtual;
}
