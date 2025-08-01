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
import {ICommonErrors} from "../common/interfaces/ICommonErrors.sol";
import {CommonConstants} from "../common/CommonConstants.sol";
import {Storage as s} from "./libraries/Storage.sol";

/**
 * @title Rebalancer
 * @notice Abstract contract for rebalancing pool liquidity
 */
abstract contract Rebalancer is IRebalancer, PoolBase {
    using s for s.Rebalancer;
    using SafeERC20 for IERC20;

    uint256 private constant DEFAULT_GAS_LIMIT = 300_000;

    function fillDeficit(uint256 liquidityAmountToFill) external returns (uint256 iouTokensToMint) {
        require(liquidityAmountToFill > 0, ICommonErrors.InvalidAmount());

        uint256 deficit = getDeficit();
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
            (deficitFillable *
                (CommonConstants.BPS_DENOMINATOR + CommonConstants.REBALANCER_PREMIUM_BPS)) /
            CommonConstants.BPS_DENOMINATOR;
        i_iouToken.mint(msg.sender, iouTokensToMint);

        emit DeficitFilled(deficitFillable, iouTokensToMint);
        return iouTokensToMint;
    }

    function takeSurplus(
        uint256 iouTokensToBurn
    ) external returns (uint256 liquidityTokensToReceive) {
        require(iouTokensToBurn > 0, ICommonErrors.InvalidAmount());

        uint256 currentSurplus = getSurplus();
        require(currentSurplus > 0, NoSurplusToTake());

        liquidityTokensToReceive = iouTokensToBurn;
        i_iouToken.burnFrom(msg.sender, iouTokensToBurn);

        IERC20(i_liquidityToken).safeTransfer(msg.sender, liquidityTokensToReceive);

        emit SurplusTaken(liquidityTokensToReceive, iouTokensToBurn);
        return liquidityTokensToReceive;
    }

    function getIOUToken() external view returns (address) {
        return address(i_iouToken);
    }

    function bridgeIOU(
        uint256 iouTokenAmount,
        uint24 destinationChainSelector
    ) external payable returns (bytes32 messageId) {
        require(iouTokenAmount > 0, ICommonErrors.InvalidAmount());

        s.Rebalancer storage s_rebalancer = s.rebalancer();

        // Validate destination pool exists
        address destinationPoolAddress = s_rebalancer.dstPools[destinationChainSelector];
        require(destinationPoolAddress != address(0), InvalidDestinationChain());

        // Burn IOU tokens from sender first (fail early if insufficient balance)
        i_iouToken.burnFrom(msg.sender, iouTokenAmount);

        // Encode message data
        bytes memory messageData = abi.encode(iouTokenAmount, msg.sender);
        bytes memory crossChainMessage = abi.encode(ConceroMessageType.BRIDGE_IOU, messageData);

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

        s_rebalancer.totalIouSent += iouTokenAmount;

        emit IOUBridged(msg.sender, destinationChainSelector, iouTokenAmount, messageId);
        return messageId;
    }

    function _handleConceroReceiveBridgeIou(
        bytes32 messageId,
        uint24 sourceChainSelector,
        bytes calldata messageData
    ) internal override {
        (uint256 iouTokenAmount, address receiver) = abi.decode(messageData, (uint256, address));

        require(iouTokenAmount > 0, ICommonErrors.InvalidAmount());

        i_iouToken.mint(receiver, iouTokenAmount);

        s.rebalancer().totalIouReceived += iouTokenAmount;

        emit IOUReceived(messageId, sourceChainSelector, receiver, iouTokenAmount);
    }

    function getMessageFee(
        uint24 destinationChainSelector,
        address destinationPoolAddress,
        uint256 gasLimitForExecution
    ) external view returns (uint256 crossChainMessageFee) {
        require(destinationPoolAddress != address(0), ICommonErrors.InvalidAmount());
        require(gasLimitForExecution > 0, ICommonErrors.InvalidAmount());

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
}
