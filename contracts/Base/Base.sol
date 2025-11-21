// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {ICommonErrors} from "../common/interfaces/ICommonErrors.sol";
import {ConceroClient} from "@concero/v2-contracts/contracts/ConceroClient/ConceroClient.sol";
import {MessageCodec} from "@concero/v2-contracts/contracts/common/libraries/MessageCodec.sol";
import {ConceroOwnable} from "../common/ConceroOwnable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IOUToken} from "../Rebalancer/IOUToken.sol";
import {IBase} from "./interfaces/IBase.sol";
import {CommonConstants} from "../common/CommonConstants.sol";
import {Storage as rs} from "../Rebalancer/libraries/Storage.sol";
import {Storage as s} from "./libraries/Storage.sol";
import {BridgeCodec} from "../common/libraries/BridgeCodec.sol";

abstract contract Base is IBase, ConceroClient, ConceroOwnable {
    using s for s.Base;
    using s for rs.Rebalancer;
    using MessageCodec for bytes;
    using BridgeCodec for bytes32;
    using BridgeCodec for bytes;

    error ValidatorAlreadySet(address currentValidator);
    error RelayerAlreadySet(address currentRelayer);
    error ValidatorIsNotSet();
    error RelayerIsNotSet();

    uint32 private constant SECONDS_IN_DAY = 86400;

    address internal immutable i_liquidityToken;
    IOUToken internal immutable i_iouToken;
    uint8 internal immutable i_liquidityTokenDecimals;
    uint24 internal immutable i_chainSelector;

    modifier onlyLancaKeeper() {
        s.Base storage s_base = s.base();
        require(
            msg.sender == s_base.lancaKeeper,
            ICommonErrors.UnauthorizedCaller(msg.sender, s_base.lancaKeeper)
        );

        _;
    }

    constructor(
        address liquidityToken,
        address conceroRouter,
        address iouToken,
        uint8 liquidityTokenDecimals,
        uint24 chainSelector
    ) ConceroClient(conceroRouter) {
        i_liquidityToken = liquidityToken;
        i_liquidityTokenDecimals = liquidityTokenDecimals;
        i_chainSelector = chainSelector;
        i_iouToken = IOUToken(iouToken);
    }

    receive() external payable {}

    /*   VIEW FUNCTIONS   */

    function getActiveBalance() public view virtual returns (uint256) {
        return IERC20(i_liquidityToken).balanceOf(address(this)) - s.base().totalLancaFeeInLiqToken;
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

    function getLancaKeeper() public view returns (address) {
        return s.base().lancaKeeper;
    }

    function getRelayerLib() public view returns (address) {
        return s.base().relayerLib;
    }

    function getValidatorLib() public view returns (address) {
        return s.base().validatorLib;
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

    function getLpFee(uint256 amount) public pure returns (uint256) {
        return (amount * CommonConstants.LP_PREMIUM_BPS) / CommonConstants.BPS_DENOMINATOR;
    }

    function getLancaFee(uint256 amount) public pure returns (uint256) {
        return
            (amount * (CommonConstants.LANCA_BRIDGE_PREMIUM_BPS)) / CommonConstants.BPS_DENOMINATOR;
    }

    function getRebalancerFee(uint256 amount) public pure returns (uint256) {
        return (amount * CommonConstants.REBALANCER_PREMIUM_BPS) / CommonConstants.BPS_DENOMINATOR;
    }

    /*   ADMIN FUNCTIONS   */

    function setDstPool(uint24 chainSelector, bytes32 dstPool) public virtual onlyOwner {
        require(chainSelector != i_chainSelector, ICommonErrors.InvalidChainSelector());
        require(dstPool != bytes32(0), ICommonErrors.AddressShouldNotBeZero());

        s.base().dstPools[chainSelector] = dstPool;
    }

    function setLancaKeeper(address lancaKeeper) external onlyOwner {
        s.base().lancaKeeper = lancaKeeper;
    }

    function setRelayerLib(address relayerLib) external onlyOwner {
        s.Base storage s_base = s.base();

        require(relayerLib != address(0), ICommonErrors.AddressShouldNotBeZero());
        require(s_base.relayerLib == address(0), RelayerAlreadySet(s_base.relayerLib));

        s_base.relayerLib = relayerLib;
        _setIsRelayerAllowed(relayerLib, true);
    }

    function removeRelayerLib() external onlyOwner {
        s.Base storage s_base = s.base();

        address currentRelayer = s_base.relayerLib;
        require(currentRelayer != address(0), RelayerIsNotSet());

        _setIsRelayerAllowed(currentRelayer, false);

        s_base.relayerLib = address(0);
    }

    function setValidatorLib(address validatorLib) external onlyOwner {
        s.Base storage s_base = s.base();

        require(validatorLib != address(0), ICommonErrors.AddressShouldNotBeZero());
        require(s_base.validatorLib == address(0), ValidatorAlreadySet(s_base.validatorLib));

        s_base.validatorLib = validatorLib;

        _setRequiredValidatorsCount(1);
        _setIsValidatorAllowed(validatorLib, true);
    }

    function removeValidatorLib() external onlyOwner {
        s.Base storage s_base = s.base();

        address currentValidator = s_base.validatorLib;
        require(currentValidator != address(0), ValidatorIsNotSet());

        _setRequiredValidatorsCount(0);
        _setIsValidatorAllowed(currentValidator, false);

        s_base.validatorLib = address(0);
    }

    /*   INTERNAL FUNCTIONS   */

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
