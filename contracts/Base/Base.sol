// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {ICommonErrors} from "../common/interfaces/ICommonErrors.sol";
import {ConceroClient} from "@concero/v2-contracts/contracts/ConceroClient/ConceroClient.sol";
import {MessageCodec} from "@concero/v2-contracts/contracts/common/libraries/MessageCodec.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IOUToken} from "../Rebalancer/IOUToken.sol";
import {IBase} from "./interfaces/IBase.sol";
import {Storage as rs} from "../Rebalancer/libraries/Storage.sol";
import {Storage as s} from "./libraries/Storage.sol";
import {BridgeCodec} from "../common/libraries/BridgeCodec.sol";
import {Decimals} from "../common/libraries/Decimals.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";

/// @title Lanca Base Liquidity Pool
/// @notice Abstract base contract for Lanca liquidity pools that integrate Concero cross-chain messaging.
/// @dev
/// - Manages:
///   * underlying liquidity token and IOU token,
///   * per-chain destination pools,
///   * fees (LP / rebalancer / Lanca bridge) in tenths of a basis point,
///   * target balance and surplus/deficit calculations,
///   * access control for admin and keeper roles.
/// - Extends:
///   * `ConceroClient` for Concero message handling,
///   * `AccessControlUpgradeable` for RBAC,
///   * `IBase` as a shared pool interface.
/// - Fee precision:
///   * `BPS_DENOMINATOR = 100_000`
///   * 1 unit of `*_FeeBps` = 0.1 bps = 0.001%.
abstract contract Base is IBase, AccessControlUpgradeable, ConceroClient {
    using SafeERC20 for IERC20;
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

    /// @notice Denominator used for fee calculations.
    /// @dev
    /// - `fee = amount * feeBps / BPS_DENOMINATOR`.
    /// - 1 unit of `feeBps` = 0.1 bps = 0.001%.
    uint24 internal constant BPS_DENOMINATOR = 100_000;
    uint32 private constant SECONDS_IN_DAY = 86400;
    bytes32 public constant ADMIN = keccak256("ADMIN");
    bytes32 public constant LANCA_KEEPER = keccak256("LANCA_KEEPER");

    uint24 internal immutable i_chainSelector;
    address internal immutable i_liquidityToken;
    IOUToken internal immutable i_iouToken;
    uint8 internal immutable i_liquidityTokenDecimals;
    uint32 internal immutable i_liquidityTokenGasOverhead;

    constructor(
        address liquidityToken,
        address conceroRouter,
        address iouToken,
        uint24 chainSelector,
        uint32 liquidityTokenGasOverhead
    ) AccessControlUpgradeable() ConceroClient(conceroRouter) {
        i_liquidityTokenDecimals = IERC20Metadata(liquidityToken).decimals();
        i_iouToken = IOUToken(iouToken);

        require(i_iouToken.decimals() == i_liquidityTokenDecimals, InvalidLiqTokenDecimals());

        i_liquidityToken = liquidityToken;
        i_liquidityTokenGasOverhead = liquidityTokenGasOverhead;
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

    /// @notice Returns the active liquidity balance managed by this pool.
    /// @dev
    /// - Active balance = token balance
    ///   minus accumulated Lanca fees
    ///   minus accumulated rebalancing fees.
    /// @return Active liquidity token balance available for operations.
    function getActiveBalance() public view virtual returns (uint256) {
        return
            IERC20(i_liquidityToken).balanceOf(address(this)) -
            s.base().totalLancaFeeInLiqToken -
            rs.rebalancer().totalRebalancingFeeAmount;
    }

    /// @notice Returns the current surplus of the pool relative to its target balance.
    /// @dev
    /// - Surplus = max(activeBalance - targetBalance, 0).
    /// @return Surplus amount in liquidity token units.
    function getSurplus() public view returns (uint256) {
        uint256 activeBalance = getActiveBalance();
        uint256 targetBalance = getTargetBalance();

        if (activeBalance <= targetBalance) return 0;
        return activeBalance - targetBalance;
    }

    /// @notice Returns the current deficit of the pool relative to its target balance.
    /// @dev
    /// - Deficit = max(targetBalance - activeBalance, 0).
    /// @return deficit Deficit amount in liquidity token units.
    function getDeficit() public view returns (uint256 deficit) {
        uint256 targetBalance = getTargetBalance();
        uint256 activeBalance = getActiveBalance();
        deficit = activeBalance >= targetBalance ? 0 : targetBalance - activeBalance;
    }

    /// @notice Returns both deficit and surplus of the pool.
    /// @return deficit Current deficit amount.
    /// @return surplus Current surplus amount.
    function getPoolData() external view returns (uint256 deficit, uint256 surplus) {
        deficit = getDeficit();
        surplus = getSurplus();
    }

    /// @notice Returns the destination pool address (as bytes32) for a given chain selector.
    /// @param chainSelector Chain selector of the destination chain.
    /// @return Bytes32-encoded address of the destination pool.
    function getDstPool(uint24 chainSelector) public view returns (bytes32) {
        return s.base().dstPools[chainSelector];
    }

    /// @notice Returns the currently configured relayer library address.
    /// @return Address of the relayer library (or zero address if not set).
    function getRelayerLib() public view returns (address) {
        return s.base().relayerLib;
    }

    /// @notice Returns the currently configured validator library address.
    /// @return Address of the validator library (or zero address if not set).
    function getValidatorLib() public view returns (address) {
        return s.base().validatorLib;
    }

    /// @notice Returns the address of the underlying liquidity token.
    /// @return Address of the ERC20 liquidity token.
    function getLiquidityToken() public view returns (address) {
        return i_liquidityToken;
    }

    function getTargetBalance() public view returns (uint256) {
        return s.base().targetBalance;
    }

    /// @notice Returns liquidity flow statistics for yesterday.
    /// @dev
    /// - Daily buckets are indexed by day number from `getYesterdayStartTimestamp()`.
    /// @return LiqTokenDailyFlow struct for the previous day.
    function getYesterdayFlow() public view returns (LiqTokenDailyFlow memory) {
        return s.base().flowByDay[getYesterdayStartTimestamp()];
    }

    /// @notice Returns the start-of-day index for today.
    /// @dev
    /// - Calculated as `block.timestamp / 86400`.
    /// @return Day index representing the current day.
    function getTodayStartTimestamp() public view returns (uint32) {
        return uint32(block.timestamp) / SECONDS_IN_DAY;
    }

    /// @notice Returns the start-of-day index for yesterday.
    /// @dev
    /// - Defined as `getTodayStartTimestamp() - 1`.
    /// @return Day index representing the previous day.
    function getYesterdayStartTimestamp() public view returns (uint32) {
        return getTodayStartTimestamp() - 1;
    }

    /// @notice Calculates the LP fee in tokens for a given amount.
    /// @dev
    /// - Uses `lpFeeBps` from storage with `BPS_DENOMINATOR = 100_000`.
    /// - Effective fee in bps = `lpFeeBps * 0.1`.
    /// @param amount Amount in liquidity token units.
    /// @return LP fee amount in tokens.
    function getLpFee(uint256 amount) public view returns (uint256) {
        return (amount * s.base().lpFeeBps) / BPS_DENOMINATOR;
    }

    /// @notice Calculates the Lanca bridge fee in tokens for a given amount.
    /// @dev
    /// - Uses `lancaBridgeFeeBps` from storage with `BPS_DENOMINATOR = 100_000`.
    /// @param amount Amount in liquidity token units.
    /// @return Lanca bridge fee amount in tokens.
    function getLancaFee(uint256 amount) public view returns (uint256) {
        return (amount * (s.base().lancaBridgeFeeBps)) / BPS_DENOMINATOR;
    }

    /// @notice Calculates the rebalancer fee in tokens for a given amount.
    /// @dev
    /// - Uses `rebalancerFeeBps` from storage with `BPS_DENOMINATOR = 100_000`.
    /// @param amount Amount in liquidity token units.
    /// @return Rebalancer fee amount in tokens.
    function getRebalancerFee(uint256 amount) public view returns (uint256) {
        return (amount * s.base().rebalancerFeeBps) / BPS_DENOMINATOR;
    }

    /// @notice Returns the configured rebalancer fee in tenths of a basis point.
    /// @dev
    /// - Effective fee in bps = `rebalancerFeeBps * 0.1`.
    /// @return Fee value where 1 unit = 0.1 bps.
    function getRebalancerFeeBps() external view returns (uint8) {
        return s.base().rebalancerFeeBps;
    }

    /// @notice Returns the configured LP fee in tenths of a basis point.
    /// @dev
    /// - Effective fee in bps = `lpFeeBps * 0.1`.
    /// @return Fee value where 1 unit = 0.1 bps.
    function getLpFeeBps() external view returns (uint8) {
        return s.base().lpFeeBps;
    }

    /// @notice Returns the configured Lanca bridge fee in tenths of a basis point.
    /// @dev
    /// - Effective fee in bps = `lancaBridgeFeeBps * 0.1`.
    /// @return Fee value where 1 unit = 0.1 bps.
    function getLancaBridgeFeeBps() external view returns (uint8) {
        return s.base().lancaBridgeFeeBps;
    }

    function getWithdrawableLancaFee() external view returns (uint256) {
        return s.base().totalLancaFeeInLiqToken;
    }

    /*   ADMIN FUNCTIONS   */

    /// @notice Sets the destination pool address for a given chain selector.
    /// @dev
    /// - Only callable by accounts with `ADMIN` role.
    /// - `chainSelector` must not equal local `i_chainSelector`.
    /// - `dstPool` must be non-zero.
    /// @param chainSelector Destination chain selector.
    /// @param dstPool Bytes32-encoded destination pool address.
    function setDstPool(uint24 chainSelector, bytes32 dstPool) public virtual onlyRole(ADMIN) {
        require(chainSelector != i_chainSelector, ICommonErrors.InvalidChainSelector());
        require(dstPool != bytes32(0), ICommonErrors.AddressShouldNotBeZero());

        s.base().dstPools[chainSelector] = dstPool;
    }

    /// @notice Sets the relayer library used by this pool and allows it in Concero client.
    /// @dev
    /// - Only callable by `ADMIN`.
    /// - Can only be set once while `relayerLib` is zero.
    /// @param relayerLib Address of the relayer library.
    function setRelayerLib(address relayerLib) external onlyRole(ADMIN) {
        s.Base storage s_base = s.base();

        require(relayerLib != address(0), ICommonErrors.AddressShouldNotBeZero());
        require(s_base.relayerLib == address(0), RelayerAlreadySet(s_base.relayerLib));

        s_base.relayerLib = relayerLib;
        _setIsRelayerLibAllowed(relayerLib, true);
    }

    /// @notice Removes the currently configured relayer library and disallows it in Concero client.
    /// @dev Only callable by `ADMIN`.
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

    /// @notice Sets the rebalancer fee in tenths of a basis point.
    /// @dev
    /// - Only callable by `ADMIN`.
    /// - 1 unit = 0.1 bps.
    /// @param rebalancerFeeBps New rebalancer fee value.
    function setRebalancerFeeBps(uint8 rebalancerFeeBps) external onlyRole(ADMIN) {
        s.base().rebalancerFeeBps = rebalancerFeeBps;
    }

    /// @notice Sets the LP fee in tenths of a basis point.
    /// @dev
    /// - Only callable by `ADMIN`.
    /// - 1 unit = 0.1 bps.
    /// @param lpFeeBps New LP fee value.
    function setLpFeeBps(uint8 lpFeeBps) external onlyRole(ADMIN) {
        s.base().lpFeeBps = lpFeeBps;
    }

    /// @notice Sets the Lanca bridge fee in tenths of a basis point.
    /// @dev
    /// - Only callable by `ADMIN`.
    /// - 1 unit = 0.1 bps.
    /// @param lancaBridgeFeeBps New Lanca bridge fee value.
    function setLancaBridgeFeeBps(uint8 lancaBridgeFeeBps) external onlyRole(ADMIN) {
        s.base().lancaBridgeFeeBps = lancaBridgeFeeBps;
    }

    /// @notice Withdraws Lanca fees from the pool.
    /// @dev
    /// - Only callable by `ADMIN`.
    /// - Withdraws to the caller address.
    /// - Emits `LancaFeeWithdrawn`.
    function withdrawLancaFee() external onlyRole(ADMIN) {
        s.Base storage s_base = s.base();

        uint256 totalLancaFee = s_base.totalLancaFeeInLiqToken;

        s_base.totalLancaFeeInLiqToken = 0;

        IERC20(i_liquidityToken).safeTransfer(msg.sender, totalLancaFee);

        emit LancaFeeWithdrawn(msg.sender, totalLancaFee);
    }

    /*   INTERNAL FUNCTIONS   */

    /// @notice Converts an amount from a source token's decimals to the local liquidity token decimals.
    /// @dev Uses `Decimals.toDecimals` helper for safe scaling.
    /// @param amountInSrcDecimals Amount expressed in `srcDecimals` units.
    /// @param srcDecimals Decimals of the source token.
    /// @return Amount scaled to `i_liquidityTokenDecimals`.
    function _toLocalDecimals(
        uint256 amountInSrcDecimals,
        uint8 srcDecimals
    ) internal view returns (uint256) {
        return amountInSrcDecimals.toDecimals(srcDecimals, i_liquidityTokenDecimals);
    }

    /// @dev
    /// - Validates the Concero message sender by checking that:
    ///   * `evmSrcChainData().sender` matches the configured `dstPools[sourceChainSelector]`.
    /// - Decodes the Concero message type and dispatches to the appropriate handler:
    ///   * `BRIDGE_IOU`              → `_handleConceroReceiveBridgeIou`,
    ///   * `SEND_SNAPSHOT`           → `_handleConceroReceiveSnapshot`,
    ///   * `BRIDGE`                  → `_handleConceroReceiveBridgeLiquidity`,
    ///   * `UPDATE_TARGET_BALANCE`   → `_handleConceroReceiveUpdateTargetBalance`.
    /// - Reverts with `InvalidConceroMessageType` for unknown message types.
    /// @param messageReceipt Packed Concero message receipt delivered by the router.
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
            _handleConceroReceiveUpdateTargetBalance(sourceChainSelector, message);
        } else {
            revert InvalidConceroMessageType();
        }
    }

    /// @notice Handles incoming IOU-bridge messages from another chain.
    /// @dev
    /// - Must be implemented by concrete pool contracts.
    /// - Typical responsibilities:
    ///   * mint/burn IOU tokens,
    ///   * update accounting for cross-chain IOU positions.
    /// @param messageId Unique Concero message identifier.
    /// @param sourceChainSelector Chain selector of the source chain.
    /// @param messageData IOU-bridge specific payload.
    function _handleConceroReceiveBridgeIou(
        bytes32 messageId,
        uint24 sourceChainSelector,
        bytes calldata messageData
    ) internal virtual;

    /// @notice Handles incoming snapshot messages from another chain.
    /// @dev
    /// - Must be implemented by concrete pool contracts.
    /// - Typically used to synchronize liquidity/TVL information between chains.
    /// @param sourceChainSelector Chain selector of the source chain.
    /// @param messageData Snapshot-specific payload.
    function _handleConceroReceiveSnapshot(
        uint24 sourceChainSelector,
        bytes calldata messageData
    ) internal virtual;

    /// @notice Handles incoming liquidity-bridge messages from another chain.
    /// @dev
    /// - Must be implemented by concrete pool contracts.
    /// - Typically transfers liquidity in/out and updates LP positions.
    /// @param messageId Unique Concero message identifier.
    /// @param sourceChainSelector Chain selector of the source chain.
    /// @param nonce Concero message nonce for replay protection/tracking.
    /// @param messageData Bridge-specific payload.
    function _handleConceroReceiveBridgeLiquidity(
        bytes32 messageId,
        uint24 sourceChainSelector,
        uint256 nonce,
        bytes calldata messageData
    ) internal virtual;

    /// @notice Handles incoming messages that update the pool's target balance.
    /// @dev
    /// - Must be implemented by concrete pool contracts.
    /// - Typically updates `targetBalance` or related rebalancing parameters.
    /// @param sourceChainSelector Chain selector of the source chain.
    /// @param messageData Payload containing new target balance or config.
    function _handleConceroReceiveUpdateTargetBalance(
        uint24 sourceChainSelector,
        bytes calldata messageData
    ) internal virtual;
}
