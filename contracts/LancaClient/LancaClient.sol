// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {ERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";

import {ILancaClient} from "./interfaces/ILancaClient.sol";

abstract contract LancaClient is ILancaClient, ERC165 {
    error InvalidLancaPool(address pool);

    address internal immutable i_lancaPool;

    constructor(address lancaPool) {
        require(lancaPool != address(0), InvalidLancaPool(lancaPool));
        i_lancaPool = lancaPool;
    }

    function supportsInterface(
        bytes4 interfaceId
    ) public view virtual override(ERC165) returns (bool) {
        return
            interfaceId == type(ILancaClient).interfaceId || super.supportsInterface(interfaceId);
    }

    function lancaReceive(address token, address from, uint256 value, bytes memory data) external {
        require(msg.sender == i_lancaPool, InvalidLancaPool(msg.sender));
        _lancaReceive(token, from, value, data);
    }

    function _lancaReceive(
        address token,
        address from,
        uint256 value,
        bytes memory data
    ) internal virtual;
}
