// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {
    ConceroTypes,
    IConceroRouter
} from "@concero/v2-contracts/contracts/interfaces/IConceroRouter.sol";

import {ReentrancyGuard} from "./ReentrancyGuard.sol";
import {ILancaBridge} from "./interfaces/ILancaBridge.sol";
import {Base, IERC20} from "../Base/Base.sol";
import {ICommonErrors} from "../common/interfaces/ICommonErrors.sol";
import {ILancaClient} from "../LancaClient/interfaces/ILancaClient.sol";
import {Storage as s} from "../Base/libraries/Storage.sol";
import {Storage as rs} from "../Rebalancer/libraries/Storage.sol";
import {Storage as bs} from "./libraries/Storage.sol";

abstract contract LancaBridge is ILancaBridge, Base, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using s for s.Base;
    using rs for rs.Rebalancer;
    using bs for bs.Bridge;

    uint256 internal constant BRIDGE_GAS_OVERHEAD = 100_000;

    function bridge(
        address tokenReceiver,
        uint256 tokenAmount,
        uint24 dstChainSelector,
        uint256 dstGasLimit,
        bytes calldata dstCallData
    ) external payable nonReentrant returns (bytes32 messageId) {
        bs.Bridge storage s_bridge = bs.bridge();

        address dstPool = s.base().dstPools[dstChainSelector];
        require(dstPool != address(0), InvalidDstPool());

        uint256 tokenAmountToBridge = _chargeTotalLancaFee(tokenAmount);

        _postInflow(tokenAmountToBridge);
        _deposit(msg.sender, tokenAmount);

        messageId = _sendMessage(
            tokenReceiver,
            tokenAmountToBridge,
            dstChainSelector,
            dstGasLimit,
            s_bridge.sentNonces[dstChainSelector]++,
            dstCallData,
            dstPool
        );

        s_bridge.totalSent += tokenAmount;

        emit TokenSent(
            messageId,
            dstChainSelector,
            i_liquidityToken,
            msg.sender,
            tokenReceiver,
            tokenAmountToBridge,
            dstPool
        );
    }

    /*   INTERNAL FUNCTIONS   */

    function _sendMessage(
        address tokenReceiver,
        uint256 tokenAmount,
        uint24 dstChainSelector,
        uint256 dstGasLimit,
        uint256 nonce,
        bytes calldata dstCallData,
        address dstPool
    ) internal returns (bytes32 messageId) {
        require(
            (dstGasLimit == 0 && dstCallData.length == 0) ||
                (dstGasLimit > 0 && dstCallData.length > 0),
            InvalidDstGasLimitOrCallData()
        );

        bytes memory messageData = abi.encode(
            i_liquidityToken,
            msg.sender,
            tokenReceiver,
            tokenAmount,
            dstGasLimit,
            nonce,
            dstCallData
        );

        messageId = IConceroRouter(i_conceroRouter).conceroSend{value: msg.value}(
            dstChainSelector,
            false,
            address(0),
            ConceroTypes.EvmDstChainData({
                receiver: dstPool,
                gasLimit: BRIDGE_GAS_OVERHEAD + dstGasLimit
            }),
            abi.encode(ConceroMessageType.BRIDGE, messageData)
        );
    }

    function _handleConceroReceiveBridgeLiquidity(
        bytes32 messageId,
        uint24 sourceChainSelector,
        bytes memory messageData
    ) internal override nonReentrant {
        bs.Bridge storage s_bridge = bs.bridge();

        (
            address token,
            address tokenSender,
            address tokenReceiver,
            uint256 tokenAmount,
            uint256 dstGasLimit,
            uint256 nonce,
            bytes memory dstCallData
        ) = _decodeMessage(messageData);

        uint256 existingAmount = s_bridge.receivedBridges[sourceChainSelector][nonce];

        if (existingAmount == 0) {
            s_bridge.totalReceived += tokenAmount;
        } else {
            s_bridge.totalReceived = s_bridge.totalReceived - existingAmount + tokenAmount;
            emit SrcBridgeReorged(existingAmount, tokenAmount, sourceChainSelector);
        }

        s_bridge.receivedBridges[sourceChainSelector][nonce] = tokenAmount;

        // todo: Think about adding retry and increase _postOutflow() when balance is insufficient
        require(getActiveBalance() >= tokenAmount, ICommonErrors.InvalidAmount());

        _postOutflow(tokenAmount);

        if (dstGasLimit == 0 && dstCallData.length == 0) {
            _bridgeReceive(token, tokenReceiver, tokenAmount);
        } else if (_isValidContractReceiver(tokenReceiver)) {
            _bridgeReceive(token, tokenReceiver, tokenAmount);

            ILancaClient(tokenReceiver).lancaReceive{gas: dstGasLimit}(
                token,
                tokenSender,
                tokenAmount,
                dstCallData
            );
        } else {
            revert InvalidConceroMessage();
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

    function _isValidContractReceiver(address tokenReceiver) internal view returns (bool) {
        if (
            tokenReceiver.code.length == 0 ||
            !IERC165(tokenReceiver).supportsInterface(type(ILancaClient).interfaceId)
        ) {
            return false;
        }

        return true;
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
            uint256 dstGasLimit,
            uint256 nonce,
            bytes memory dstCallData
        )
    {
        (token, tokenSender, tokenReceiver, tokenAmount, dstGasLimit, nonce, dstCallData) = abi
            .decode(messageData, (address, address, address, uint256, uint256, uint256, bytes));
    }

    function _chargeTotalLancaFee(uint256 tokenAmount) internal returns (uint256) {
        uint256 lpFee = getLpFee(tokenAmount);
        uint256 bridgeFee = getBridgeFee(tokenAmount);
        uint256 rebalancerFee = getRebalancerFee(tokenAmount);

        uint256 totalLancaFee = lpFee + bridgeFee + rebalancerFee;
        require(totalLancaFee > 0, ICommonErrors.InvalidFeeAmount());

        s.base().totalLancaFeeInLiqToken += bridgeFee;
        rs.rebalancer().totalRebalancingFee += rebalancerFee;

        return tokenAmount - totalLancaFee;
    }

    function _deposit(address tokenSender, uint256 tokenAmount) internal {
        IERC20(i_liquidityToken).safeTransferFrom(tokenSender, address(this), tokenAmount);
    }

    function _bridgeReceive(address token, address tokenReceiver, uint256 tokenAmount) internal {
        require(token == i_liquidityToken, InvalidToken());

        IERC20(token).safeTransfer(tokenReceiver, tokenAmount);
    }

    /*   GETTERS   */

    function getBridgeNativeFee(
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
