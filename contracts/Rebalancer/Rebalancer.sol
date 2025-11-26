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
 * @notice Abstract contract for rebalancing pool liquidity
 */
abstract contract Rebalancer is IRebalancer, Base {
    using s for s.Rebalancer;
    using bs for bs.Base;
    using SafeERC20 for IERC20;
    using BridgeCodec for bytes32;
    using BridgeCodec for address;
    using BridgeCodec for bytes;

    uint32 private constant DEFAULT_GAS_LIMIT = 150_000;

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

    function topUpRebalancingFee(uint256 amount) external onlyOwner {
        IERC20(i_liquidityToken).safeTransferFrom(msg.sender, address(this), amount);
        s.rebalancer().totalRebalancingFeeAmount += amount;
    }

    function syncRebalancingFeeWithLiquidity() external onlyOwner {
        s.Rebalancer storage s_rebalancer = s.rebalancer();

        uint256 maxNeededFee = getRebalancerFee(getSurplus());

        if (s_rebalancer.totalRebalancingFeeAmount > maxNeededFee) {
            // TODO: mb transfer excess to owner
            uint256 excess = s_rebalancer.totalRebalancingFeeAmount - maxNeededFee;
            s_rebalancer.totalRebalancingFeeAmount = maxNeededFee;
        }
    }

    /* VIEW FUNCTIONS */

    function getIOUToken() external view returns (address) {
        return address(i_iouToken);
    }

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

    function _postInflowRebalance(uint256 liquidityAmountToFill) internal virtual {}
}
