// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import {
    IConceroRouter,
    ConceroTypes
} from "@concero/v2-contracts/contracts/interfaces/IConceroRouter.sol";

import {LancaClient} from "../LancaClient/LancaClient.sol";
import {ILancaBridge} from "./interfaces/ILancaBridge.sol";
import {PoolBase, IERC20, CommonTypes} from "../PoolBase/PoolBase.sol";
import {Storage as s} from "../PoolBase/libraries/Storage.sol";
import {ICommonErrors} from "../common/interfaces/ICommonErrors.sol";

abstract contract LancaBridge is ILancaBridge, PoolBase, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using s for s.PoolBase;

    uint256 internal constant BRIDGE_GAS_OVERHEAD = 100_000;

    function bridge(
        address token,
        address tokenReceiver,
        uint256 tokenAmount,
        uint24 dstChainSelector,
        bool isTokenReceiverContract,
        uint256 dstGasLimit,
        bytes calldata dstCallData
    ) external payable nonReentrant returns (bytes32 messageId) {
        require(tokenAmount > 0, ICommonErrors.InvalidAmount());

        address dstPool = s.poolBase().dstPools[dstChainSelector];
        require(dstPool != address(0), InvalidDestinationPool());

        _postInflow(tokenAmount);
        _depositTokens(token, msg.sender, tokenAmount);

        messageId = _sendMessage(
            token,
            tokenReceiver,
            tokenAmount,
            dstChainSelector,
            isTokenReceiverContract,
            dstGasLimit,
            dstCallData,
            dstPool
        );

        emit TokenSent(
            messageId,
            dstChainSelector,
            token,
            msg.sender,
            tokenReceiver,
            tokenAmount,
            dstPool
        );
    }

    function _sendMessage(
        address token,
        address tokenReceiver,
        uint256 tokenAmount,
        uint24 dstChainSelector,
        bool isTokenReceiverContract,
        uint256 dstGasLimit,
        bytes calldata dstCallData,
        address dstPool
    ) internal returns (bytes32 messageId) {
        bytes memory bridgeData;
        if (isTokenReceiverContract) {
            bridgeData = abi.encode(token, msg.sender, tokenReceiver, tokenAmount, dstCallData);
        } else {
            bridgeData = abi.encode(token, msg.sender, tokenReceiver, tokenAmount);
        }

        bytes memory messageData = abi.encode(
            isTokenReceiverContract
                ? CommonTypes.BridgeType.CONTRACT_TRANSFER
                : CommonTypes.BridgeType.EOA_TRANSFER,
            bridgeData
        );

        messageId = IConceroRouter(i_conceroRouter).conceroSend{value: msg.value}(
            dstChainSelector,
            false,
            address(0),
            ConceroTypes.EvmDstChainData({
                receiver: dstPool,
                gasLimit: isTokenReceiverContract
                    ? BRIDGE_GAS_OVERHEAD + dstGasLimit
                    : BRIDGE_GAS_OVERHEAD
            }),
            abi.encode(CommonTypes.MessageType.BRIDGE_LIQUIDITY, messageData)
        );
    }

    function _handleConceroReceiveBridgeLiquidity(
        bytes32 messageId,
        uint24 sourceChainSelector,
        bytes memory messageData
    ) internal override nonReentrant {
        (
            address token,
            address tokenSender,
            address tokenReceiver,
            uint256 tokenAmount,
            CommonTypes.BridgeType bridgeType,
            bytes memory dstCallData
        ) = _decodeMessage(messageData);

        _postOutflow(tokenAmount);

        if (bridgeType == CommonTypes.BridgeType.CONTRACT_TRANSFER) {
            _withdrawTokens(token, tokenReceiver, tokenAmount);
            _callTokenReceiver(token, tokenSender, tokenReceiver, tokenAmount, dstCallData);
        } else {
            _withdrawTokens(token, tokenReceiver, tokenAmount);
        }

        emit BridgeDelivered(
            messageId,
            sourceChainSelector,
            token,
            tokenSender,
            tokenReceiver,
            tokenAmount
        );
    }

    function _decodeMessage(
        bytes memory messageData
    )
        internal
        pure
        returns (
            address token,
            address tokenSender,
            address tokenReceiver,
            uint256 tokenAmount,
            CommonTypes.BridgeType bridgeType,
            bytes memory dstCallData
        )
    {
        bytes memory bridgeData;
        (bridgeType, bridgeData) = abi.decode(messageData, (CommonTypes.BridgeType, bytes));

        if (bridgeType == CommonTypes.BridgeType.EOA_TRANSFER) {
            (token, tokenSender, tokenReceiver, tokenAmount) = abi.decode(
                bridgeData,
                (address, address, address, uint256)
            );
        } else if (bridgeType == CommonTypes.BridgeType.CONTRACT_TRANSFER) {
            (token, tokenSender, tokenReceiver, tokenAmount, dstCallData) = abi.decode(
                bridgeData,
                (address, address, address, uint256, bytes)
            );
        } else {
            revert InvalidBridgeType();
        }
    }

    function _depositTokens(address token, address tokenSender, uint256 tokenAmount) internal {
        require(token == i_liquidityToken, OnlyAllowedTokens());

        IERC20(token).safeTransferFrom(tokenSender, address(this), tokenAmount);
    }

    function _withdrawTokens(address token, address tokenReceiver, uint256 tokenAmount) internal {
        require(token == i_liquidityToken, OnlyAllowedTokens());
        require(tokenAmount <= getActiveBalance(), ICommonErrors.InvalidAmount());

        IERC20(token).safeTransfer(tokenReceiver, tokenAmount);
    }

    function _callTokenReceiver(
        address token,
        address tokenSender,
        address tokenReceiver,
        uint256 tokenAmount,
        bytes memory dstCallData
    ) internal {
        bytes4 expectedSelector = LancaClient(tokenReceiver).lancaReceive(
            token,
            tokenSender,
            tokenAmount,
            dstCallData
        );

        require(
            expectedSelector == LancaClient.lancaReceive.selector,
            LancaClient.InvalidSelector()
        );
    }
}
