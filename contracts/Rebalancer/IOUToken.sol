// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

/**
 * @title IOUToken
 * @notice Token representing debt owed by child pools to rebalancers
 */
contract IOUToken is ERC20, ERC20Burnable, AccessControl {
    bytes32 public constant POOL_ROLE = keccak256("POOL_ROLE");

    constructor(address admin, address pool) ERC20("LancaIOU-USDC", "LIOU-USDC") {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(POOL_ROLE, pool);
    }

    function mint(address to, uint256 amount) public onlyRole(POOL_ROLE) {
        _mint(to, amount);
    }

    function burnFrom(address from, uint256 amount) public override onlyRole(POOL_ROLE) {
        _burn(from, amount);
    }
}
