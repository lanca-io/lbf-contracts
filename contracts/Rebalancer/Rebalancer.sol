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

/**
 * @title Rebalancer
 * @notice Abstract contract for rebalancing pool liquidity
 */
abstract contract Rebalancer is IRebalancer, Base {
    using s for s.Rebalancer;
    using bs for bs.Base;
    using SafeERC20 for IERC20;

    uint32 private constant DEFAULT_GAS_LIMIT = 300_000;

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

        uint256 rebalancerFee = getRebalancerFee(iouTokensToBurn);
        uint256 liquidityTokensToReceive = iouTokensToBurn + rebalancerFee;

        if (liquidityTokensToReceive > getActiveBalance()) {
            iouTokensToBurn = (iouTokensToBurn * getActiveBalance()) / liquidityTokensToReceive;
            rebalancerFee = getRebalancerFee(iouTokensToBurn);
            liquidityTokensToReceive = iouTokensToBurn + rebalancerFee;
        }

        i_iouToken.burnFrom(msg.sender, iouTokensToBurn);
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
        bs.Base storage s_base = bs.base();

        // Validate destination pool exists
        address destinationPoolAddress = s_base.dstPools[destinationChainSelector];
        require(destinationPoolAddress != address(0), InvalidDestinationChain());

        // Burn IOU tokens from sender first (fail early if insufficient balance)
        i_iouToken.burnFrom(msg.sender, iouTokenAmount);

        // Encode message data
        bytes memory messageData = abi.encode(iouTokenAmount, msg.sender);
        bytes memory crossChainMessage = abi.encode(ConceroMessageType.BRIDGE_IOU, messageData);

        IConceroRouter.MessageRequest memory messageRequest = IConceroRouter.MessageRequest({
            dstChainSelector: destinationChainSelector,
            srcBlockConfirmations: type(uint64).max,
            feeToken: address(0),
            dstChainData: MessageCodec.encodeEvmDstChainData(
                destinationPoolAddress,
                DEFAULT_GAS_LIMIT
            ),
            validatorLibs: s_base.validatorLibs[destinationChainSelector],
            relayerLib: s_base.relayerLibs[destinationChainSelector],
            validatorConfigs: new bytes[](1), // TODO: or validatorLibs.length?
            relayerConfig: new bytes(0),
            payload: crossChainMessage
        });

        uint256 messageFee = IConceroRouter(i_conceroRouter).getMessageFee(messageRequest);
        messageId = IConceroRouter(i_conceroRouter).conceroSend{value: messageFee}(messageRequest);

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
        bs.Base storage s_base = bs.base();
        address destinationPoolAddress = bs.base().dstPools[destinationChainSelector];

        return
            IConceroRouter(i_conceroRouter).getMessageFee(
                IConceroRouter.MessageRequest({
                    dstChainSelector: destinationChainSelector,
                    srcBlockConfirmations: type(uint64).max,
                    feeToken: address(0),
                    dstChainData: MessageCodec.encodeEvmDstChainData(
                        destinationPoolAddress,
                        DEFAULT_GAS_LIMIT
                    ),
                    validatorLibs: s_base.validatorLibs[destinationChainSelector],
                    relayerLib: s_base.relayerLibs[destinationChainSelector],
                    validatorConfigs: new bytes[](1), // TODO: or validatorLibs.length?
                    relayerConfig: new bytes(0),
                    payload: abi.encode(ConceroMessageType.BRIDGE_IOU, abi.encode(1e18, msg.sender))
                })
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
