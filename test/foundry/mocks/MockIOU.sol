// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {IOUToken} from "contracts/Rebalancer/IOUToken.sol";

contract MockIOU is IOUToken {
    uint8 private immutable i_decimals;

    error InvalidDecimals();

    constructor(address admin, address minter, uint8 _decimals) IOUToken(admin, minter) {
        require(_decimals > 0 && _decimals < type(uint8).max, InvalidDecimals());

        i_decimals = _decimals;
    }

    function decimals() public view override returns (uint8) {
        return i_decimals;
    }
}
