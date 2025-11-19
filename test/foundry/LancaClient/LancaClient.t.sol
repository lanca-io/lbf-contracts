// SPDX-License-Identifier: UNLICENSED
/* solhint-disable func-name-mixedcase */
pragma solidity 0.8.28;

import {ERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";

import {ILancaClient} from "contracts/LancaClient/interfaces/ILancaClient.sol";
import {LancaClient} from "contracts/LancaClient/LancaClient.sol";
import {LancaBridgeBase} from "../LancaBridge/LancaBridgeBase.sol";

contract LancaClientWrapper is LancaClient {
    constructor(address lancaPool) LancaClient(lancaPool) {}

    function _lancaReceive(
        bytes32 id,
        uint24 srcChainSelector,
        bytes32 sender,
        uint256 amount,
        bytes memory data
    ) internal override {}
}

contract LancaClientTest is LancaBridgeBase {
    function test_lancaClient_RevertsInvalidLancaPool() public {
        vm.expectRevert(LancaClient.InvalidLancaPool.selector);

        new LancaClientWrapper(address(0));

        LancaClientWrapper lancaClient = new LancaClientWrapper(address(s_parentPool));

        vm.expectRevert(LancaClient.InvalidLancaPool.selector);

        lancaClient.lancaReceive(DEFAULT_MESSAGE_ID, PARENT_POOL_CHAIN_SELECTOR, bytes32(0), 0, "");
    }

    function test_supportsInterface() public {
        LancaClientWrapper lancaClient = new LancaClientWrapper(address(s_parentPool));

        assertEq(lancaClient.supportsInterface(type(ILancaClient).interfaceId), true);
        assertEq(lancaClient.supportsInterface(type(ERC165).interfaceId), true);
    }
}
