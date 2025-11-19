// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {LancaClient} from "contracts/LancaClient/LancaClient.sol";
import {BridgeCodec} from "contracts/common/libraries/BridgeCodec.sol";

contract LancaClientMock is LancaClient {
    using BridgeCodec for bytes32;

    struct ReceivedCall {
        bytes32 id;
        uint24 srcChainSelector;
        address sender;
        uint256 amount;
        bytes data;
    }

    ReceivedCall[] public receivedCalls;
    bool public shouldRevert;
    string public revertReason;

    constructor(address lancaPool) LancaClient(lancaPool) {}

    function setShouldRevert(bool _shouldRevert, string memory _revertReason) external {
        shouldRevert = _shouldRevert;
        revertReason = _revertReason;
    }

    function getReceivedCallsCount() external view returns (uint256) {
        return receivedCalls.length;
    }

    function getReceivedCall(uint256 index) external view returns (ReceivedCall memory) {
        return receivedCalls[index];
    }

    function _lancaReceive(
        bytes32 id,
        uint24 srcChainSelector,
        bytes32 sender,
        uint256 amount,
        bytes memory data
    ) internal override {
        if (shouldRevert) {
            revert(revertReason);
        }

        receivedCalls.push(
            ReceivedCall({
                id: id,
                srcChainSelector: srcChainSelector,
                sender: sender.toAddress(),
                amount: amount,
                data: data
            })
        );
    }
}
