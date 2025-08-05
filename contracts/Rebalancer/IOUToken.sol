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
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    constructor(address admin, address minter) ERC20("LancaIOU-USDC", "LIOU-USDC") {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(MINTER_ROLE, minter);
    }

    function mint(address to, uint256 amount) public onlyRole(MINTER_ROLE) {
        _mint(to, amount);
    }

    function burn(address account, uint256 amount) public onlyRole(MINTER_ROLE) {
        _burn(account, amount);
    }

    function decimals() public view virtual override returns (uint8) {
        return 6;
    }
}
