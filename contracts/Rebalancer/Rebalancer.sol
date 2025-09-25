// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {IRebalancer} from "./interfaces/IRebalancer.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Base} from "../Base/Base.sol";
import {ConceroTypes} from "@concero/v2-contracts/contracts/ConceroClient/ConceroTypes.sol";
import {IConceroRouter} from "@concero/v2-contracts/contracts/interfaces/IConceroRouter.sol";
import {ICommonErrors} from "../common/interfaces/ICommonErrors.sol";
import {Storage as s} from "./libraries/Storage.sol";
import {Storage as bs} from "../Base/libraries/Storage.sol";

/**
 * @title Rebalancer
 * @notice Abstract contract for rebalancing pool liquidity
 */
abstract contract Rebalancer is IRebalancer, Base {
    using s for s.Rebalancer;
    using bs for bs.Base;
    using SafeERC20 for IERC20;

    uint256 private constant DEFAULT_GAS_LIMIT = 300_000;

    function fillDeficit(uint256 liquidityAmountToFill) external {
        require(liquidityAmountToFill > 0, ICommonErrors.AmountIsZero());
        require(
            getDeficit() >= liquidityAmountToFill,
            AmountExceedsDeficit(getDeficit(), liquidityAmountToFill)
        );

        // Safe transfer liquidity tokens from caller to the pool
        IERC20(i_liquidityToken).safeTransferFrom(msg.sender, address(this), liquidityAmountToFill);

        i_iouToken.mint(msg.sender, liquidityAmountToFill);

        _postInflowRebalance(liquidityAmountToFill);

        emit DeficitFilled(msg.sender, liquidityAmountToFill);
    }

    function takeSurplus(uint256 iouTokensToBurn) external returns (uint256) {
        require(iouTokensToBurn > 0, ICommonErrors.AmountIsZero());
        require(
            getSurplus() >= iouTokensToBurn,
            AmountExceedsSurplus(getSurplus(), iouTokensToBurn)
        );

        i_iouToken.burnFrom(msg.sender, iouTokensToBurn);

        uint256 rebalancerFee = getRebalancerFee(iouTokensToBurn);
        s.Rebalancer storage s_rebalancer = s.rebalancer();

        require(
            s_rebalancer.totalRebalancingFee >= rebalancerFee,
            InsufficientRebalancingFee(s_rebalancer.totalRebalancingFee, rebalancerFee)
        );

        s_rebalancer.totalRebalancingFee -= rebalancerFee;

        uint256 liquidityTokensToReceive = iouTokensToBurn + rebalancerFee;

        IERC20(i_liquidityToken).safeTransfer(msg.sender, liquidityTokensToReceive);

        emit SurplusTaken(msg.sender, liquidityTokensToReceive, iouTokensToBurn);
        return liquidityTokensToReceive;
    }

    function bridgeIOU(
        uint256 iouTokenAmount,
        uint24 destinationChainSelector
    ) external payable returns (bytes32 messageId) {
        require(iouTokenAmount > 0, ICommonErrors.AmountIsZero());

        s.Rebalancer storage s_rebalancer = s.rebalancer();

        // Validate destination pool exists
        address destinationPoolAddress = bs.base().dstPools[destinationChainSelector];
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

        emit IOUBridged(messageId, msg.sender, destinationChainSelector, iouTokenAmount);
        return messageId;
    }

    /* VIEW FUNCTIONS */

    function getIOUToken() external view returns (address) {
        return address(i_iouToken);
    }

    function getBridgeIouNativeFee(
        uint24 destinationChainSelector
    ) external view returns (uint256) {
        return
            IConceroRouter(i_conceroRouter).getMessageFee(
                destinationChainSelector,
                false,
                address(0),
                ConceroTypes.EvmDstChainData({receiver: address(0), gasLimit: DEFAULT_GAS_LIMIT})
            );
    }

    /* INTERNAL FUNCTIONS */

    function _handleConceroReceiveBridgeIou(
        bytes32 messageId,
        uint24 sourceChainSelector,
        bytes memory messageData
    ) internal override {
        (uint256 iouTokenAmount, address receiver) = abi.decode(messageData, (uint256, address));

        i_iouToken.mint(receiver, iouTokenAmount);

        s.rebalancer().totalIouReceived += iouTokenAmount;

        emit IOUReceived(messageId, receiver, sourceChainSelector, iouTokenAmount);
    }

    function _postInflowRebalance(uint256 liquidityAmountToFill) internal virtual {}
}
