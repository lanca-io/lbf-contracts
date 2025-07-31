// SPDX-License-Identifier: UNLICENSED
/**
 * @title Security Reporting
 * @notice If you discover any security vulnerabilities, please report them responsibly.
 * @contact email: security@concero.io
 */
pragma solidity 0.8.28;

import {ILancaClient} from "./interfaces/ILancaClient.sol";

abstract contract LancaClient is ILancaClient {
    error InvalidLancaPool(address pool);
    error InvalidSelector();

    address internal immutable i_lancaPool;

    constructor(address lancaPool) {
        require(lancaPool != address(0), InvalidLancaPool(lancaPool));
        i_lancaPool = lancaPool;
    }

    function lancaReceive(
        address token,
        address from,
        uint256 value,
        bytes memory data
    ) external returns (bytes4) {
        require(msg.sender == i_lancaPool, InvalidLancaPool(msg.sender));
        _lancaReceive(token, from, value, data);

        return ILancaClient.lancaReceive.selector;
    }

    function _lancaReceive(
        address token,
        address from,
        uint256 value,
        bytes memory data
    ) internal virtual;
}
