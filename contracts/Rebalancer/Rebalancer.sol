// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {IRebalancer} from "./interfaces/IRebalancer.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IOUToken} from "./IOUToken.sol";
import {PoolBase} from "../PoolBase/PoolBase.sol";
import {ConceroClient} from "@concero/v2-contracts/contracts/ConceroClient/ConceroClient.sol";
import {ConceroTypes} from "@concero/v2-contracts/contracts/ConceroClient/ConceroTypes.sol";
import {IConceroRouter} from "@concero/v2-contracts/contracts/interfaces/IConceroRouter.sol";
import {CommonTypes} from "../common/CommonTypes.sol";
import {Storage as s} from "./libraries/Storage.sol";

/**
 * @title Rebalancer
 * @notice Abstract contract for rebalancing pool liquidity
 */
abstract contract Rebalancer is IRebalancer, PoolBase, ConceroClient {
    using s for s.Rebalancer;

    uint256 public constant BPS_DENOMINATOR = 10_000;
    uint256 public constant REBALANCER_PREMIUM_BPS = 10;
    uint256 private constant DEFAULT_GAS_LIMIT = 300_000;

    IOUToken internal immutable i_iouToken;

    constructor(address iouToken, address conceroRouter) ConceroClient(conceroRouter) {
        i_iouToken = IOUToken(iouToken);
    }

    function fillDeficit(uint256 amount) external returns (uint256 iouAmount) {
        uint256 deficit = getCurrentDeficit();
        if (deficit == 0) revert NoDeficitToFill();

        // Cap the amount to the actual deficit
        if (amount > deficit) {
            amount = deficit;
        }

        // Transfer liquidity tokens from caller to the pool
        IERC20(i_liquidityToken).transferFrom(msg.sender, address(this), amount);

        // Mint IOU tokens to the caller
        iouAmount = (amount * (BPS_DENOMINATOR + REBALANCER_PREMIUM_BPS)) / BPS_DENOMINATOR;
        i_iouToken.mint(msg.sender, iouAmount);

        emit DeficitFilled(amount, iouAmount);
        return iouAmount;
    }

    function takeSurplus(uint256 iouAmount) external returns (uint256 amount) {
        uint256 surplus = getCurrentSurplus();
        if (surplus == 0) revert NoSurplusToTake();

        // Calculate equivalent amount of surplus tokens
        amount = iouAmount;

        // Cap the amount to the actual surplus
        if (amount > surplus) {
            amount = surplus;
            iouAmount = amount;
        }

        // Burn IOU tokens from caller
        i_iouToken.burnFrom(msg.sender, iouAmount);

        // Transfer liquidity tokens to the caller
        bool success = IERC20(i_liquidityToken).transfer(msg.sender, amount);
        if (!success) revert TransferFailed();

        emit SurplusTaken(amount, iouAmount);
        return amount;
    }

    function getIOUToken() external view returns (address) {
        return address(i_iouToken);
    }

    function bridgeIOU(
        uint256 amount,
        uint24 chainSelector
    ) external payable returns (bytes32 messageId) {
        // Validate destination pool exists
        address dstPool = s.rebalancer().dstPools[chainSelector];
        if (dstPool == address(0)) revert InvalidDestinationChain();

        // Validate amount is not zero
        if (amount == 0) revert InvalidAmount();

        // Burn IOU tokens from sender
        i_iouToken.burnFrom(msg.sender, amount);

        // Encode message data
        bytes memory messageData = abi.encode(amount, msg.sender);
        bytes memory message = abi.encode(CommonTypes.MessageType.BRIDGE_IOU, messageData);

        // Prepare destination chain data
        ConceroTypes.EvmDstChainData memory dstChainData = ConceroTypes.EvmDstChainData({
            receiver: dstPool,
            gasLimit: DEFAULT_GAS_LIMIT
        });

        // Call conceroSend on router
        messageId = IConceroRouter(i_conceroRouter).conceroSend{value: msg.value}(
            chainSelector,
            false, // shouldFinaliseSrc
            address(0), // feeToken (native)
            dstChainData,
            message
        );
        emit IOUBridged(msg.sender, chainSelector, amount, messageId);

        return messageId;
    }

    function _conceroReceive(
        bytes32 messageId,
        uint24 srcChainSelector,
        bytes calldata sender,
        bytes calldata message
    ) internal override {
        // Decode sender address
        address senderAddress = abi.decode(sender, (address));

        // Validate sender is authorized pool
        if (s.rebalancer().dstPools[srcChainSelector] != senderAddress) revert UnauthorizedSender();

        // Decode message type
        (CommonTypes.MessageType messageType, bytes memory data) = abi.decode(
            message,
            (CommonTypes.MessageType, bytes)
        );

        if (messageType == CommonTypes.MessageType.BRIDGE_IOU) {
            // Decode bridge data
            (uint256 amount, address receiver) = abi.decode(data, (uint256, address));

            // Mint IOU tokens to receiver
            i_iouToken.mint(receiver, amount);

            emit IOUReceived(srcChainSelector, receiver, amount, messageId);
        } else {
            revert InvalidMessageType();
        }
    }

    function setDstPool(uint24 chainSelector, address poolAddress) external {
        // TODO: Add access control - only owner/admin should call this
        s.rebalancer().dstPools[chainSelector] = poolAddress;
        emit DstPoolSet(chainSelector, poolAddress);
    }

    function getMessageFee(
        uint24 dstChainSelector,
        address dstPool,
        uint256 gasLimit
    ) external view returns (uint256) {
        ConceroTypes.EvmDstChainData memory dstChainData = ConceroTypes.EvmDstChainData({
            receiver: dstPool,
            gasLimit: gasLimit
        });

        (bool success, bytes memory returnData) = i_conceroRouter.staticcall(
            abi.encodeWithSignature(
                "getMessageFee(uint24,bool,address,(address,uint256))",
                dstChainSelector,
                false, // shouldFinaliseSrc
                address(0), // feeToken (native)
                dstChainData
            )
        );

        if (!success) revert GetMessageFeeFailed();

        return abi.decode(returnData, (uint256));
    }

    function dstPools(uint24 chainSelector) external view returns (address) {
        return s.rebalancer().dstPools[chainSelector];
    }
}
