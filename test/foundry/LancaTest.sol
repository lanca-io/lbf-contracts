// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {IConceroRouter} from "@concero/v2-contracts/contracts/interfaces/IConceroRouter.sol";
import {MessageCodec} from "@concero/v2-contracts/contracts/common/libraries/MessageCodec.sol";

import {Test} from "forge-std/src/Test.sol";
import {LancaBaseScript} from "./scripts/LancaBaseScript.s.sol";

import {IBase} from "contracts/Base/interfaces/IBase.sol";
import {Base} from "contracts/Base/Base.sol";

abstract contract LancaTest is LancaBaseScript {
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
        validatorLibs[0] = validatorLib;

        return
            IConceroRouter.MessageRequest({
                dstChainSelector: dstChainSelector,
                srcBlockConfirmations: srcBlockConfirmations,
                feeToken: feeToken,
                dstChainData: MessageCodec.encodeEvmDstChainData(dstPool, dstChainGasLimit),
                validatorLibs: validatorLibs,
                relayerLib: relayerLib,
                validatorConfigs: new bytes[](1),
                relayerConfig: new bytes(0),
                payload: payload
            });
    }

    function _setRelayerLib(uint24 dstChainSelector, address client) internal {
        vm.prank(deployer);
        Base(payable(client)).setRelayerLib(dstChainSelector, relayerLib, new bytes(1), true);
    }

    function _setValidatorLibs(uint24 dstChainSelector, address client) internal {
        uint24[] memory dstChainSelectors = new uint24[](1);
        dstChainSelectors[0] = dstChainSelector;

        bool[] memory isAllowed = new bool[](1);
        isAllowed[0] = true;

        IBase.ValidatorLibs[] memory validatorLibsStruct = new IBase.ValidatorLibs[](1);
        validatorLibsStruct[0] = IBase.ValidatorLibs({
            validatorLibs: validatorLibs,
            isAllowed: isAllowed,
            requiredValidatorsCount: 1
        });

        vm.prank(deployer);
        Base(payable(client)).setValidatorLibs(dstChainSelectors, validatorLibsStruct);
    }
}
