// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Base} from "../Base/Base.sol";
import {BridgeCodec} from "../common/libraries/BridgeCodec.sol";
import {ICommonErrors} from "../common/interfaces/ICommonErrors.sol";
import {IConceroRouter} from "@concero/v2-contracts/contracts/interfaces/IConceroRouter.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ILancaBridge} from "./interfaces/ILancaBridge.sol";
import {ILancaClient} from "../LancaClient/interfaces/ILancaClient.sol";
import {MessageCodec} from "@concero/v2-contracts/contracts/common/libraries/MessageCodec.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Storage as bs} from "./libraries/Storage.sol";
import {Storage as rs} from "../Rebalancer/libraries/Storage.sol";
import {Storage as s} from "../Base/libraries/Storage.sol";

abstract contract LancaBridge is ILancaBridge, Base {
    using SafeERC20 for IERC20;
    using BridgeCodec for address;
    using BridgeCodec for bytes32;
    using BridgeCodec for bytes;
    using MessageCodec for bytes;
    using s for s.Base;
    using rs for rs.Rebalancer;
    using bs for bs.Bridge;

    uint32 internal constant BRIDGE_GAS_OVERHEAD = 100_000;

    function bridge(
        uint256 tokenAmount,
        uint24 dstChainSelector,
        bytes calldata dstChainData,
        bytes calldata payload
    ) external payable returns (bytes32 messageId) {
        s.Base storage s_base = s.base();

        bytes32 dstPool = s_base.dstPools[dstChainSelector];
        require(dstPool != bytes32(0), InvalidDstChainSelector(dstChainSelector));

        IERC20(i_liquidityToken).safeTransferFrom(msg.sender, address(this), tokenAmount);

        {
            uint256 amountAfterFee = _chargeTotalLancaFee(tokenAmount);

            messageId = _sendMessage(
                amountAfterFee,
                dstChainSelector,
                payload,
                dstChainData,
                dstPool,
                s_base
            );

            s_base.totalLiqTokenSent += amountAfterFee;
            s_base.flowByDay[getTodayStartTimestamp()].inflow += amountAfterFee;
        }

        emit BridgeSent(messageId, dstChainSelector, dstChainData, msg.sender, tokenAmount);
    }

    /*   INTERNAL FUNCTIONS   */

    function _sendMessage(
        uint256 tokenAmount,
        uint24 dstChainSelector,
        bytes calldata payload,
        bytes calldata userDstChainData,
        bytes32 dstPool,
        s.Base storage s_base
    ) internal returns (bytes32) {
        address[] memory validatorLibs = new address[](1);
        validatorLibs[0] = s_base.validatorLib;

        IConceroRouter.MessageRequest memory messageRequest = IConceroRouter.MessageRequest({
            dstChainSelector: dstChainSelector,
            srcBlockConfirmations: 0,
            feeToken: address(0),
            dstChainData: _buildDstChainData(userDstChainData, dstPool, payload.length),
            validatorLibs: validatorLibs,
            relayerLib: s_base.relayerLib,
            validatorConfigs: new bytes[](1),
            relayerConfig: new bytes(0),
            payload: BridgeCodec.encodeBridgeData(
                msg.sender,
                tokenAmount,
                i_liquidityTokenDecimals,
                userDstChainData,
                payload
            )
        });

        return IConceroRouter(i_conceroRouter).conceroSend{value: msg.value}(messageRequest);
    }

    function _buildDstChainData(
        bytes calldata userDstChainData,
        bytes32 dstPool,
        uint256 payloadLength
    ) internal pure returns (bytes memory) {
        (, uint32 userDstChainGasLimit) = MessageCodec.decodeEvmDstChainData(userDstChainData);

        require(
            (userDstChainGasLimit == 0 && payloadLength == 0) ||
                (userDstChainGasLimit > 0 && payloadLength > 0),
            InvalidDstGasLimitOrCallData()
        );

        return
            MessageCodec.encodeEvmDstChainData(
                dstPool.toAddress(),
                BRIDGE_GAS_OVERHEAD + userDstChainGasLimit
            );
    }

    function _handleConceroReceiveBridgeLiquidity(
        bytes32 messageId,
        uint24 srcChainSelector,
        uint256 nonce,
        bytes calldata messageData
    ) internal override {
        (
            uint256 tokenAmount,
            uint8 decimals,
            bytes32 tokenSender,
            bytes calldata dstChainData,
            bytes calldata payload
        ) = messageData.decodeBridgeData();

        tokenAmount = _toLocalDecimals(tokenAmount, decimals);

        _handleInflow(tokenAmount, srcChainSelector, nonce);

        _deliverBridge(
            messageId,
            tokenAmount,
            srcChainSelector,
            tokenSender,
            dstChainData,
            payload
        );
    }

    function _deliverBridge(
        bytes32 messageId,
        uint256 tokenAmount,
        uint24 srcChainSelector,
        bytes32 tokenSender,
        bytes calldata dstChainData,
        bytes calldata payload
    ) internal {
        (address receiver, uint32 dstGasLimit) = dstChainData.decodeEvmDstChainData();

        bool shouldCallHook = _validateBridgeParams(dstGasLimit, receiver, payload);

        IERC20(i_liquidityToken).safeTransfer(receiver, tokenAmount);

        if (shouldCallHook) {
            ILancaClient(receiver).lancaReceive{gas: dstGasLimit}(
                messageId,
                srcChainSelector,
                tokenSender,
                tokenAmount,
                payload
            );
        }

        emit BridgeDelivered(messageId, tokenAmount);
    }

    function _handleInflow(uint256 tokenAmount, uint24 srcChainSelector, uint256 nonce) internal {
        bs.Bridge storage s_bridge = bs.bridge();
        s.Base storage s_base = s.base();

        require(getActiveBalance() >= tokenAmount, ICommonErrors.InvalidAmount());

        uint256 existingAmount = s_bridge.receivedBridges[srcChainSelector][nonce];

        if (existingAmount == 0) {
            s_base.totalLiqTokenReceived += tokenAmount;
        } else {
            s_base.totalLiqTokenReceived =
                s_base.totalLiqTokenReceived -
                existingAmount +
                tokenAmount;
            emit SrcBridgeReorged(srcChainSelector, existingAmount);
        }

        s_bridge.receivedBridges[srcChainSelector][nonce] = tokenAmount;
        s.base().flowByDay[getTodayStartTimestamp()].outflow += tokenAmount;
    }

    function _validateBridgeParams(
        uint32 dstGasLimit,
        address receiver,
        bytes calldata payload
    ) internal view returns (bool) {
        bool shouldCallHook = !(dstGasLimit == 0 && payload.length == 0);

        if (shouldCallHook && !_isValidContractReceiver(receiver)) {
            revert InvalidConceroMessage();
        }

        return shouldCallHook;
    }

    function _isValidContractReceiver(address tokenReceiver) internal view returns (bool) {
        if (
            tokenReceiver.code.length == 0 ||
            !IERC165(tokenReceiver).supportsInterface(type(ILancaClient).interfaceId)
        ) {
            return false;
        }

        return true;
    }

    function _chargeTotalLancaFee(uint256 tokenAmount) internal returns (uint256) {
        uint256 bridgeFee = getLancaFee(tokenAmount);
        uint256 rebalancerFee = getRebalancerFee(tokenAmount);

        uint256 totalLancaFee = getLpFee(tokenAmount) + bridgeFee + rebalancerFee;

        s.base().totalLancaFeeInLiqToken += bridgeFee;
        rs.rebalancer().totalRebalancingFeeAmount += rebalancerFee;

        return tokenAmount - totalLancaFee;
    }

    /*   GETTERS   */

    function getBridgeNativeFee(
        uint256 /* tokenAmount */,
        uint24 dstChainSelector,
        bytes calldata dstChainData,
        bytes calldata payload
    ) external view returns (uint256) {
        s.Base storage s_base = s.base();

        bytes32 dstPool = s_base.dstPools[dstChainSelector];
        require(dstPool != bytes32(0), InvalidDstChainSelector(dstChainSelector));

        address[] memory validatorLibs = new address[](1);
        validatorLibs[0] = s_base.validatorLib;

        return
            IConceroRouter(i_conceroRouter).getMessageFee(
                IConceroRouter.MessageRequest({
                    dstChainSelector: dstChainSelector,
                    srcBlockConfirmations: 0,
                    feeToken: address(0),
                    dstChainData: _buildDstChainData(dstChainData, dstPool, payload.length),
                    validatorLibs: validatorLibs,
                    relayerLib: s_base.relayerLib,
                    validatorConfigs: new bytes[](1),
                    relayerConfig: new bytes(0),
                    payload: BridgeCodec.encodeBridgeData(
                        msg.sender,
                        1,
                        i_liquidityTokenDecimals,
                        dstChainData,
                        payload
                    )
                })
            );
    }
}
