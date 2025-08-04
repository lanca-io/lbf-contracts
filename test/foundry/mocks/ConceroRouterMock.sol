// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {IConceroRouter} from "@concero/v2-contracts/contracts/interfaces/IConceroRouter.sol";
import {ConceroTypes} from "@concero/v2-contracts/contracts/ConceroClient/ConceroTypes.sol";

contract ConceroRouterMock is IConceroRouter {
    error InvalidFeeValue();

    function conceroSend(
        uint24 dstChainSelector,
        bool shouldFinaliseSrc,
        address feeToken,
        ConceroTypes.EvmDstChainData memory,
        bytes memory message
    ) external payable returns (bytes32) {
        require(msg.value == _getFee(), InvalidFeeValue());

        return
            keccak256(
                abi.encode(block.number, dstChainSelector, shouldFinaliseSrc, feeToken, message)
            );
    }

    function getMessageFee(
        uint24,
        bool,
        address,
        ConceroTypes.EvmDstChainData memory
    ) external pure returns (uint256) {
        return _getFee();
    }

    function _getFee() internal pure returns (uint256) {
        return 0.0001 ether;
    }
}
