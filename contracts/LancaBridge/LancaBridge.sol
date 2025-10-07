// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {
    ConceroTypes,
    IConceroRouter
} from "@concero/v2-contracts/contracts/interfaces/IConceroRouter.sol";

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

    uint256 internal constant BRIDGE_GAS_OVERHEAD = 300_000;

    function bridge(
        address tokenReceiver,
        uint256 tokenAmount,
        uint24 dstChainSelector,
        uint256 dstGasLimit,
        bytes calldata dstCallData
    ) external payable nonReentrant returns (bytes32 messageId) {
        bs.Bridge storage s_bridge = bs.bridge();

        address dstPool = s.base().dstPools[dstChainSelector];
        require(dstPool != address(0), InvalidDstChainSelector());

        IERC20(i_liquidityToken).safeTransferFrom(msg.sender, address(this), tokenAmount);

        uint256 amountAfterFee = _chargeTotalLancaFee(tokenAmount);

        messageId = _sendMessage(
            tokenReceiver,
            amountAfterFee,
            dstChainSelector,
            dstGasLimit,
            s_bridge.sentNonces[dstChainSelector]++,
            dstCallData,
            dstPool
        );

        s_bridge.totalSent += amountAfterFee;
        s.base().flowByDay[getTodayStartTimestamp()].inflow += amountAfterFee;

        emit BridgeSent(
            messageId,
            dstChainSelector,
            msg.sender,
            tokenReceiver,
            tokenAmount,
            dstGasLimit
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
            address tokenSender,
            address tokenReceiver,
            uint256 tokenAmount,
            uint256 dstGasLimit,
            uint256 nonce,
            bytes memory dstCallData
        ) = abi.decode(messageData, (address, address, uint256, uint256, uint256, bytes));

        require(getActiveBalance() >= tokenAmount, ICommonErrors.InvalidAmount());

        uint256 existingAmount = s_bridge.receivedBridges[sourceChainSelector][nonce];

        if (existingAmount == 0) {
            s_bridge.totalReceived += tokenAmount;
        } else {
            s_bridge.totalReceived = s_bridge.totalReceived - existingAmount + tokenAmount;
            emit SrcBridgeReorged(sourceChainSelector, existingAmount);
        }

        s_bridge.receivedBridges[sourceChainSelector][nonce] = tokenAmount;
        s.base().flowByDay[getTodayStartTimestamp()].outflow += tokenAmount;

        bool shouldCallHook = !(dstGasLimit == 0 && dstCallData.length == 0);

        if (shouldCallHook && !_isValidContractReceiver(tokenReceiver)) {
            revert InvalidConceroMessage();
        }

        IERC20(i_liquidityToken).safeTransfer(tokenReceiver, tokenAmount);

        if (shouldCallHook) {
            ILancaClient(tokenReceiver).lancaReceive{gas: dstGasLimit}(
                messageId,
                sourceChainSelector,
                tokenSender,
                tokenAmount,
                dstCallData
            );
        }

        emit BridgeDelivered(messageId, tokenAmount);
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

        return tokenAmount - totalLancaFee;
    }

    /*   GETTERS   */

    function getBridgeNativeFee(
        uint24 dstChainSelector,
        uint256 dstGasLimit
    ) external view returns (uint256) {
        return
            IConceroRouter(i_conceroRouter).getMessageFee(
                dstChainSelector,
                false, // shouldFinaliseSrc
                address(0), // feeToken (native)
                ConceroTypes.EvmDstChainData({
                    receiver: s.base().dstPools[dstChainSelector],
                    gasLimit: BRIDGE_GAS_OVERHEAD + dstGasLimit
                })
            );
    }
}
