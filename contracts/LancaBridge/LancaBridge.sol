// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {
    ConceroTypes,
    IConceroRouter
} from "@concero/v2-contracts/contracts/interfaces/IConceroRouter.sol";

import {ReentrancyGuard} from "./ReentrancyGuard.sol";
import {ILancaBridge} from "./interfaces/ILancaBridge.sol";
import {CommonConstants} from "../common/CommonConstants.sol";
import {LancaClient} from "../LancaClient/LancaClient.sol";
import {PoolBase, IERC20, CommonTypes} from "../PoolBase/PoolBase.sol";
import {ICommonErrors} from "../common/interfaces/ICommonErrors.sol";
import {Storage as s} from "../PoolBase/libraries/Storage.sol";
import {Storage as rs} from "../Rebalancer/libraries/Storage.sol";

abstract contract LancaBridge is ILancaBridge, PoolBase, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using s for s.PoolBase;
    using rs for rs.Rebalancer;

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
        address dstPool = s.poolBase().dstPools[dstChainSelector];
        require(dstPool != address(0), InvalidDestinationPool());

        uint256 tokenAmountToBridge = _chargeTotalLancaFee(tokenAmount);

        _postInflow(tokenAmountToBridge);
        _deposit(token, msg.sender, tokenAmount);

        messageId = _sendMessage(
            token,
            tokenReceiver,
            tokenAmountToBridge,
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
            tokenAmountToBridge,
            dstPool
        );
    }

    /*   INTERNAL FUNCTIONS   */

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

        // Think about adding retry and increase _postOutflow() when balance is insufficient
        require(getActiveBalance() >= tokenAmount, ICommonErrors.InvalidAmount());

        _postOutflow(tokenAmount);

        if (bridgeType == CommonTypes.BridgeType.CONTRACT_TRANSFER) {
            _bridgeReceive(token, tokenReceiver, tokenAmount);
            _callTokenReceiver(token, tokenSender, tokenReceiver, tokenAmount, dstCallData);
        } else {
            _bridgeReceive(token, tokenReceiver, tokenAmount);
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

    function _chargeTotalLancaFee(uint256 tokenAmount) internal returns (uint256) {
        uint256 lpFee = getLpFee(tokenAmount);
        uint256 bridgeFee = getBridgeFee(tokenAmount);
        uint256 rebalancerFee = getRebalancerFee(tokenAmount);

        uint256 totalLancaFee = lpFee + bridgeFee + rebalancerFee;
        require(totalLancaFee > 0, ICommonErrors.InvalidFeeAmount());

        s.poolBase().totalLancaFeeInLiqToken += bridgeFee;
        rs.rebalancer().totalRebalancingFee += rebalancerFee;

        return tokenAmount - totalLancaFee;
    }

    function _deposit(address token, address tokenSender, uint256 tokenAmount) internal {
        require(token == i_liquidityToken, OnlyAllowedTokens());

        IERC20(token).safeTransferFrom(tokenSender, address(this), tokenAmount);
    }

    function _bridgeReceive(address token, address tokenReceiver, uint256 tokenAmount) internal {
        require(token == i_liquidityToken, OnlyAllowedTokens());

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

    /*   GETTERS   */

    function getMessageFeeForContractCall(
        uint24 dstChainSelector,
        address dstPool,
        uint256 dstGasLimit
    ) external view returns (uint256) {
        return
            IConceroRouter(i_conceroRouter).getMessageFee(
                dstChainSelector,
                false, // shouldFinaliseSrc
                address(0), // feeToken (native)
                ConceroTypes.EvmDstChainData({
                    receiver: dstPool,
                    gasLimit: BRIDGE_GAS_OVERHEAD + dstGasLimit
                })
            );
    }
}
