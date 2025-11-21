// SPDX-License-Identifier: UNLICENSED
/**
 * @title Security Reporting
 * @notice If you discover any security vulnerabilities, please report them responsibly.
 * @contact email: security@concero.io
 */
pragma solidity 0.8.28;

import {ICommonErrors} from "./interfaces/ICommonErrors.sol";

abstract contract ConceroOwnable {
    address internal immutable i_owner;

    modifier onlyOwner() {
        require(msg.sender == i_owner, ICommonErrors.UnauthorizedCaller(msg.sender, i_owner));
        _;
    }

    constructor() {
        i_owner = msg.sender;
    }

    function getOwner() public view returns (address) {
        return i_owner;
    }
}
