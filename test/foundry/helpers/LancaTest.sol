// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {LancaBaseTest} from "./LancaBaseTest.sol";
import {Base} from "contracts/Base/Base.sol";
import {IBase} from "contracts/Base/interfaces/IBase.sol";
import {IConceroRouter} from "@concero/v2-contracts/contracts/interfaces/IConceroRouter.sol";
import {MessageCodec} from "@concero/v2-contracts/contracts/common/libraries/MessageCodec.sol";

abstract contract LancaTest is LancaBaseTest {
    function _buildMessageRequest(
        bytes memory messagePayload,
        uint24 dstChainSelector,
        address dstPool
    ) internal view returns (IConceroRouter.MessageRequest memory) {
        return
            _buildMessageRequest(
                messagePayload,
                dstChainSelector,
                dstPool,
                300_000,
                type(uint64).max,
                address(0)
            );
    }

    function _buildMessageRequest(
        bytes memory payload,
        uint24 dstChainSelector,
        address dstPool,
        uint32 dstChainGasLimit,
        uint64 srcBlockConfirmations,
        address feeToken
    ) internal view returns (IConceroRouter.MessageRequest memory) {
        address[] memory validatorLibs = new address[](1);
        validatorLibs[0] = s_validatorLib;

        return
            IConceroRouter.MessageRequest({
                dstChainSelector: dstChainSelector,
                srcBlockConfirmations: srcBlockConfirmations,
                feeToken: feeToken,
                dstChainData: MessageCodec.encodeEvmDstChainData(dstPool, dstChainGasLimit),
                validatorLibs: validatorLibs,
                relayerLib: s_relayerLib,
                validatorConfigs: new bytes[](1),
                relayerConfig: new bytes(0),
                payload: payload
            });
    }

    function _setRelayerLib(address client) internal {
        vm.prank(s_deployer);
        Base(payable(client)).setRelayerLib(s_relayerLib);
    }

    function _setValidatorLibs(address client) internal {
        vm.prank(s_deployer);
        Base(payable(client)).setValidatorLib(s_validatorLib);
    }
}
