// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {IRebalancer} from "./interfaces/IRebalancer.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
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
    using SafeERC20 for IERC20;

    uint256 public constant BPS_DENOMINATOR = 10_000;
    uint256 public constant REBALANCER_PREMIUM_BPS = 10;
    uint256 private constant DEFAULT_GAS_LIMIT = 300_000;

    IOUToken internal immutable i_iouToken;

    constructor(address iouToken, address conceroRouter) ConceroClient(conceroRouter) {
        i_iouToken = IOUToken(iouToken);
    }

    function fillDeficit(uint256 liquidityAmountToFill) external returns (uint256 iouTokensToMint) {
        require(liquidityAmountToFill > 0, InvalidAmount());

        uint256 deficit = getCurrentDeficit();
        require(deficit > 0, NoDeficitToFill());

        // Cap the amount to the actual deficit to prevent over-filling
        uint256 deficitFillable = liquidityAmountToFill;
        if (deficitFillable > deficit) {
            deficitFillable = deficit;
        }

        // Safe transfer liquidity tokens from caller to the pool
        IERC20(i_liquidityToken).safeTransferFrom(msg.sender, address(this), deficitFillable);

        // Calculate IOU tokens to mint with premium
        iouTokensToMint =
            (deficitFillable * (BPS_DENOMINATOR + REBALANCER_PREMIUM_BPS)) / BPS_DENOMINATOR;
        i_iouToken.mint(msg.sender, iouTokensToMint);

        emit DeficitFilled(deficitFillable, iouTokensToMint);
        return iouTokensToMint;
    }

    function takeSurplus(
        uint256 iouTokensToBurn
    ) external returns (uint256 liquidityTokensToReceive) {
        require(iouTokensToBurn > 0, InvalidAmount());

        uint256 currentSurplus = getCurrentSurplus();
        require(currentSurplus > 0, NoSurplusToTake());

        // Calculate equivalent amount of surplus tokens (1:1 ratio)
        liquidityTokensToReceive = iouTokensToBurn;
        uint256 actualIouTokensToBurn = iouTokensToBurn;

        // Cap the amount to the actual surplus
        if (liquidityTokensToReceive > currentSurplus) {
            liquidityTokensToReceive = currentSurplus;
            actualIouTokensToBurn = currentSurplus;
        }

        // Burn IOU tokens from caller first (fail early if insufficient balance)
        i_iouToken.burnFrom(msg.sender, actualIouTokensToBurn);

        // Safe transfer liquidity tokens to the caller
        IERC20(i_liquidityToken).safeTransfer(msg.sender, liquidityTokensToReceive);

        emit SurplusTaken(liquidityTokensToReceive, actualIouTokensToBurn);
        return liquidityTokensToReceive;
    }

    function getIOUToken() external view returns (address) {
        return address(i_iouToken);
    }

    function bridgeIOU(
        uint256 iouTokenAmount,
        uint24 destinationChainSelector
    ) external payable returns (bytes32 messageId) {
        require(iouTokenAmount > 0, InvalidAmount());

        // Validate destination pool exists
        address destinationPoolAddress = s.poolBase().dstPools[destinationChainSelector];
        require(destinationPoolAddress != address(0), InvalidDestinationChain());

        // Burn IOU tokens from sender first (fail early if insufficient balance)
        i_iouToken.burnFrom(msg.sender, iouTokenAmount);

        // Encode message data
        bytes memory messageData = abi.encode(iouTokenAmount, msg.sender);
        bytes memory crossChainMessage = abi.encode(
            CommonTypes.MessageType.BRIDGE_IOU,
            messageData
        );

        // Prepare destination chain data
        ConceroTypes.EvmDstChainData memory destinationChainData = ConceroTypes.EvmDstChainData({
            receiver: destinationPoolAddress,
            gasLimit: DEFAULT_GAS_LIMIT
        });

        // Call conceroSend on router
        messageId = IConceroRouter(i_conceroRouter).conceroSend{value: msg.value}(
            destinationChainSelector,
            false, // shouldFinaliseSrc
            address(0), // feeToken (native)
            destinationChainData,
            crossChainMessage
        );

        emit IOUBridged(msg.sender, destinationChainSelector, iouTokenAmount, messageId);
        return messageId;
    }

    function _conceroReceive(
        bytes32 messageId,
        uint24 sourceChainSelector,
        bytes calldata sender,
        bytes calldata message
    ) internal override {
        // Decode sender address
        address remoteSender = abi.decode(sender, (address));

        require(s.rebalancer().dstPools[sourceChainSelector] == remoteSender, UnauthorizedSender());

        // Decode message type and data
        (CommonTypes.MessageType messageType, bytes memory messageData) = abi.decode(
            message,
            (CommonTypes.MessageType, bytes)
        );

        if (messageType == CommonTypes.MessageType.BRIDGE_IOU) {
            (uint256 iouTokenAmount, address receiverAddress) = abi.decode(
                messageData,
                (uint256, address)
            );

            require(iouTokenAmount > 0, InvalidAmount());
            require(receiverAddress != address(0), InvalidAmount());

            i_iouToken.mint(receiverAddress, iouTokenAmount);

            emit IOUReceived(sourceChainSelector, receiverAddress, iouTokenAmount, messageId);
        } else {
            revert InvalidMessageType();
        }
    }

    function setDstPool(uint24 destinationChainSelector, address destinationPoolAddress) external {
        // TODO: Add access control - only owner/admin should call this
        require(destinationPoolAddress != address(0), InvalidAmount());

        s.rebalancer().dstPools[destinationChainSelector] = destinationPoolAddress;
        emit DstPoolSet(destinationChainSelector, destinationPoolAddress);
    }

    function getMessageFee(
        uint24 destinationChainSelector,
        address destinationPoolAddress,
        uint256 gasLimitForExecution
    ) external view returns (uint256 crossChainMessageFee) {
        require(destinationPoolAddress != address(0), InvalidAmount());
        require(gasLimitForExecution > 0, InvalidAmount());

        ConceroTypes.EvmDstChainData memory destinationChainData = ConceroTypes.EvmDstChainData({
            receiver: destinationPoolAddress,
            gasLimit: gasLimitForExecution
        });

        // TODO: call it using interface
        (bool success, bytes memory returnData) = i_conceroRouter.staticcall(
            abi.encodeWithSignature(
                "getMessageFee(uint24,bool,address,(address,uint256))",
                destinationChainSelector,
                false, // shouldFinaliseSrc
                address(0), // feeToken (native)
                destinationChainData
            )
        );

        require(success, GetMessageFeeFailed());

        return abi.decode(returnData, (uint256));
    }

    function dstPools(uint24 chainSelector) external view returns (address) {
        return s.rebalancer().dstPools[chainSelector];
    }
}
