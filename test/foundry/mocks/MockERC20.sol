// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockERC20 is ERC20 {
    uint8 private immutable _decimals;

    error AccountIsBlacklisted(address account);
    mapping(address => bool) private _isBlacklisted;

    modifier notBlacklisted(address _account) {
        require(!_isBlacklisted[_account], AccountIsBlacklisted(_account));
        _;
    }

    constructor(string memory name, string memory symbol, uint8 decimals_) ERC20(name, symbol) {
        _decimals = decimals_;
    }

    function decimals() public view override returns (uint8) {
        return _decimals;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) external {
        _burn(from, amount);
    }

    function transfer(
        address to,
        uint256 value
    ) public override notBlacklisted(msg.sender) notBlacklisted(to) returns (bool) {
        return super.transfer(to, value);
    }

    function transferFrom(
        address from,
        address to,
        uint256 value
    )
        public
        override
        notBlacklisted(msg.sender)
        notBlacklisted(from)
        notBlacklisted(to)
        returns (bool)
    {
        return super.transferFrom(from, to, value);
    }

    function blacklist(address account) external {
        _isBlacklisted[account] = true;
    }

    function unBlacklist(address account) external {
        _isBlacklisted[account] = false;
    }
}
