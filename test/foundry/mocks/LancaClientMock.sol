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
    bool public oog;
    uint256 public oogAmount;

    constructor(address lancaPool) LancaClient(lancaPool) {}

    function setShouldRevert(bool _shouldRevert, string memory _revertReason) external {
        shouldRevert = _shouldRevert;
        revertReason = _revertReason;
    }

    function setOOG(bool _oog, uint256 _amount) external {
        oog = _oog;
        oogAmount = _amount;
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
        bytes calldata data
    ) internal override {
        if (shouldRevert) {
            revert(revertReason);
        }

        if (oog) {
            for (uint256 i = 1000; i < oogAmount; i++) {
                assembly {
                    sstore(i, i)
                }
            }
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
