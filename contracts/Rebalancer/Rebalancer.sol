// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {IRebalancer} from "./interfaces/IRebalancer.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Base} from "../Base/Base.sol";
import {IConceroRouter} from "@concero/v2-contracts/contracts/interfaces/IConceroRouter.sol";
import {MessageCodec} from "@concero/v2-contracts/contracts/common/libraries/MessageCodec.sol";
import {ICommonErrors} from "../common/interfaces/ICommonErrors.sol";
import {Storage as s} from "./libraries/Storage.sol";
import {Storage as bs} from "../Base/libraries/Storage.sol";
import {BridgeCodec} from "../common/libraries/BridgeCodec.sol";

/**
 * @title Rebalancer
 * @notice Abstract contract providing cross-chain rebalancing logic on top of a Lanca pool.
 * @dev
 * - Extends {Base} to get core pool state and Concero client behaviour.
 * - Implements {IRebalancer} to:
 *   * allow external actors to fill liquidity deficit and receive IOU tokens,
 *   * allow IOU holders to redeem surplus liquidity,
 *   * bridge IOU tokens between pools on different chains.
 * - Tracks:
 *   * total rebalancing fee liquidity (`totalRebalancingFeeAmount`),
 *   * IOU amounts sent and received across chains.
 */
abstract contract Rebalancer is IRebalancer, Base {
    using s for s.Rebalancer;
    using bs for bs.Base;
    using SafeERC20 for IERC20;
    using BridgeCodec for bytes32;
    using BridgeCodec for address;
    using BridgeCodec for bytes;

    uint32 private constant DEFAULT_GAS_LIMIT = 150_000;

    /**
     * @notice Fills the pool deficit by depositing liquidity and minting IOU tokens.
     * @dev
     * - Validations:
     *   * `liquidityAmountToFill > 0`,
     *   * `liquidityAmountToFill <= getDeficit()`.
     * - Effects:
     *   * Transfers liquidity tokens from `msg.sender` to this contract.
     *   * Mints IOU tokens 1:1 to `msg.sender`.
     *   * Calls `_postInflowRebalance` hook for pool-specific post-inflow logic.
     * - Emits:
     *   * {DeficitFilled}
     * @param liquidityAmountToFill Amount of liquidity tokens to contribute toward the deficit.
     */
    function fillDeficit(uint256 liquidityAmountToFill) external {
        require(liquidityAmountToFill > 0, ICommonErrors.AmountIsZero());
        require(
            getDeficit() >= liquidityAmountToFill,
            AmountExceedsDeficit(getDeficit(), liquidityAmountToFill)
        );

        IERC20(i_liquidityToken).safeTransferFrom(msg.sender, address(this), liquidityAmountToFill);

        i_iouToken.mint(msg.sender, liquidityAmountToFill);

        _postInflowRebalance(liquidityAmountToFill);

        emit DeficitFilled(msg.sender, liquidityAmountToFill);
    }

    /**
     * @notice Redeems IOU tokens for underlying liquidity when the pool has surplus.
     * @dev
     * - Validations:
     *   * `iouTokensToBurn > 0`,
     *   * `iouTokensToBurn <= getSurplus()`.
     * - Fee handling:
     *   * Calculates `rebalancerFee = getRebalancerFee(iouTokensToBurn)`.
     *   * Caps fee by `totalRebalancingFeeAmount` if there is not enough fee liquidity accumulated.
     *   * Reducess `totalRebalancingFeeAmount` by the actual fee deducted.
     * - Effects:
     *   * Burns `iouTokensToBurn` IOU tokens from `msg.sender`.
     *   * Sends `iouTokensToBurn + rebalancerFee` liquidity tokens to `msg.sender`.
     * - Emits:
     *   * {SurplusTaken}
     * @param iouTokensToBurn Amount of IOU tokens to redeem.
     * @return liquidityTokensToReceive Total liquidity amount sent to the caller
     *         (principal IOU + portion of rebalancing fees).
     */
    function takeSurplus(uint256 iouTokensToBurn) external returns (uint256) {
        require(iouTokensToBurn > 0, ICommonErrors.AmountIsZero());
        require(
            getSurplus() >= iouTokensToBurn,
            AmountExceedsSurplus(getSurplus(), iouTokensToBurn)
        );

        uint256 rebalancerFee = getRebalancerFee(iouTokensToBurn);
        uint256 totalRebalancingFeeAmount = s.rebalancer().totalRebalancingFeeAmount;

        if (rebalancerFee > totalRebalancingFeeAmount) {
            rebalancerFee = totalRebalancingFeeAmount;
        }

        s.rebalancer().totalRebalancingFeeAmount -= rebalancerFee;

        uint256 liquidityTokensToReceive = iouTokensToBurn + rebalancerFee;

        i_iouToken.burnFrom(msg.sender, iouTokensToBurn);
        IERC20(i_liquidityToken).safeTransfer(msg.sender, liquidityTokensToReceive);

        emit SurplusTaken(msg.sender, liquidityTokensToReceive, iouTokensToBurn);
        return liquidityTokensToReceive;
    }

    /**
     * @notice Bridges IOU tokens from this chain to a destination pool on another chain.
     * @dev
     * - Validations:
     *   * `iouTokenAmount > 0`,
     *   * `receiver != bytes32(0)`,
     *   * destination pool is configured for `dstChainSelector`.
     * - Effects:
     *   * Burns IOU tokens from `msg.sender` on this chain.
     *   * Constructs a Concero message with `BRIDGE_IOU` payload that will:
     *     - mint IOU to `receiver` on the destination chain,
     *     - use pool-local decimals (`i_liquidityTokenDecimals`) for amount encoding.
     *   * Sends message via Concero Router and increments `totalIouSent`.
     * - Fees:
     *   * Caller must provide sufficient `msg.value` to cover the native message fee.
     *   * The exact required fee can be estimated via `getBridgeIouNativeFee`.
     * - Emits:
     *   * {IOUBridged}
     * @param receiver Bytes32-encoded receiver address on the destination chain.
     * @param dstChainSelector Chain selector of the destination chain.
     * @param iouTokenAmount Amount of IOU tokens to bridge.
     * @return messageId Concero message identifier for the bridge operation.
     */
    function bridgeIOU(
        bytes32 receiver,
        uint24 dstChainSelector,
        uint256 iouTokenAmount
    ) external payable returns (bytes32) {
        require(iouTokenAmount > 0, ICommonErrors.AmountIsZero());
        require(receiver != bytes32(0), ICommonErrors.AddressShouldNotBeZero());

        bs.Base storage s_base = bs.base();

        bytes32 dstPool = s_base.dstPools[dstChainSelector];
        require(dstPool != bytes32(0), ICommonErrors.InvalidDstChainSelector(dstChainSelector));

        i_iouToken.burnFrom(msg.sender, iouTokenAmount);

        address[] memory validatorLibs = new address[](1);
        validatorLibs[0] = s_base.validatorLib;

        IConceroRouter.MessageRequest memory messageRequest = IConceroRouter.MessageRequest({
            dstChainSelector: dstChainSelector,
            srcBlockConfirmations: type(uint64).max,
            feeToken: address(0),
            dstChainData: MessageCodec.encodeEvmDstChainData(
                dstPool.toAddress(),
                DEFAULT_GAS_LIMIT
            ),
            validatorLibs: validatorLibs,
            relayerLib: s_base.relayerLib,
            validatorConfigs: new bytes[](1),
            relayerConfig: new bytes(0),
            payload: BridgeCodec.encodeBridgeIouData(
                receiver,
                iouTokenAmount,
                i_liquidityTokenDecimals
            )
        });

        bytes32 messageId = IConceroRouter(i_conceroRouter).conceroSend{value: msg.value}(
            messageRequest
        );

        s.rebalancer().totalIouSent += iouTokenAmount;

        emit IOUBridged(messageId, msg.sender, dstChainSelector, iouTokenAmount);
        return messageId;
    }

    /* ADMIN FUNCTIONS */

    /**
     * @notice Tops up the rebalancing fee pool with additional liquidity tokens.
     * @dev
     * - Only callable by the `ADMIN` role.
     * - Effects:
     *   * Transfers liquidity tokens from `msg.sender` to this contract.
     *   * Increases `totalRebalancingFeeAmount` by `amount`.
     * @param amount Amount of liquidity tokens to add to the rebalancing fee reserve.
     */
    function topUpRebalancingFee(uint256 amount) external onlyRole(ADMIN) {
        IERC20(i_liquidityToken).safeTransferFrom(msg.sender, address(this), amount);
        s.rebalancer().totalRebalancingFeeAmount += amount;
    }

    /* VIEW FUNCTIONS */

    function getIOUToken() external view returns (address) {
        return address(i_iouToken);
    }

    /**
     * @notice Returns the native fee required to bridge IOU tokens to a given destination chain.
     * @dev
     * - This is an estimation helper for frontends and integrators.
     * - It uses a dummy payload with:
     *   * receiver = `msg.sender.toBytes32()`,
     *   * IOU amount = 1 (unit),
     *   * local decimals = `i_liquidityTokenDecimals`.
     * - The actual fee passed to `bridgeIOU` should be `>=` the value returned here.
     * - Validations:
     *   * Destination pool must be configured for `dstChainSelector`.
     * @param dstChainSelector Destination chain selector for IOU bridging.
     * @return Native token amount required to pay the Concero relayer + validators.
     */
    function getBridgeIouNativeFee(uint24 dstChainSelector) external view returns (uint256) {
        bs.Base storage s_base = bs.base();

        address destinationPoolAddress = bs.base().dstPools[dstChainSelector].toAddress();
        require(
            destinationPoolAddress != address(0),
            ICommonErrors.InvalidDstChainSelector(dstChainSelector)
        );

        address[] memory validatorLibs = new address[](1);
        validatorLibs[0] = s_base.validatorLib;

        return
            IConceroRouter(i_conceroRouter).getMessageFee(
                IConceroRouter.MessageRequest({
                    dstChainSelector: dstChainSelector,
                    srcBlockConfirmations: type(uint64).max,
                    feeToken: address(0),
                    dstChainData: MessageCodec.encodeEvmDstChainData(
                        destinationPoolAddress,
                        DEFAULT_GAS_LIMIT
                    ),
                    validatorLibs: validatorLibs,
                    relayerLib: s_base.relayerLib,
                    validatorConfigs: new bytes[](1),
                    relayerConfig: new bytes(0),
                    payload: BridgeCodec.encodeBridgeIouData(
                        msg.sender.toBytes32(),
                        1,
                        i_liquidityTokenDecimals
                    )
                })
            );
    }

    /* INTERNAL FUNCTIONS */

    /**
     * @notice Internal Concero handler for incoming IOU bridge messages.
     * @dev
     * - Called from the pool’s Concero client implementation when `BRIDGE_IOU` is received.
     * - Steps:
     *   1. Decodes `(receiver, iouTokenAmount, srcDecimals)` from `messageData`.
     *   2. Converts `iouTokenAmount` from source decimals to local decimals.
     *   3. Mints IOU tokens to `receiver` on this chain.
     *   4. Increments `totalIouReceived`.
     * - Emits:
     *   * {IOUReceived}
     * @param messageId Concero message identifier associated with this IOU bridge.
     * @param sourceChainSelector Chain selector of the source chain.
     * @param messageData Encoded `BRIDGE_IOU` payload.
     */
    function _handleConceroReceiveBridgeIou(
        bytes32 messageId,
        uint24 sourceChainSelector,
        bytes calldata messageData
    ) internal override {
        (bytes32 receiver, uint256 iouTokenAmount, uint8 srcDecimals) = messageData
            .decodeBridgeIouData();

        iouTokenAmount = _toLocalDecimals(iouTokenAmount, srcDecimals);

        i_iouToken.mint(receiver.toAddress(), iouTokenAmount);

        s.rebalancer().totalIouReceived += iouTokenAmount;

        emit IOUReceived(messageId, receiver.toAddress(), sourceChainSelector, iouTokenAmount);
    }

    /**
     * @notice Hook called after a positive liquidity inflow via `fillDeficit`.
     * @dev
     * - Default implementation is empty and can be overridden by concrete pools.
     * - Typical uses:
     *   * Parent pool may override to automatically allocate inflow
     *     towards pending withdrawals if certain conditions are met.
     * @param liquidityAmountToFill Amount of liquidity added in the inflow.
     */
    function _postInflowRebalance(uint256 liquidityAmountToFill) internal virtual {}
}
