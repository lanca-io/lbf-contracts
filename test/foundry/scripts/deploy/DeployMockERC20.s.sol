// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {Script} from "forge-std/src/Script.sol";
import {MockERC20} from "../../../../contracts/MockERC20/MockERC20.sol";

import {LancaBaseScript} from "../LancaBaseScript.s.sol";

contract DeployMockERC20 is LancaBaseScript {
    function run() external returns (address) {
        return deployERC20("USD Coin", "USDC", 6);
    }

    function deployERC20(
        string memory name,
        string memory symbol,
        uint8 decimals_
    ) public returns (address) {
        vm.startBroadcast(deployer);

        MockERC20 token = new MockERC20(name, symbol, decimals_);

        vm.stopBroadcast();

        return address(token);
    }

    function deployAndMint(
        string memory name,
        string memory symbol,
        uint8 decimals_,
        address recipient,
        uint256 amount
    ) public returns (address) {
        vm.startBroadcast(deployer);

        MockERC20 token = new MockERC20(name, symbol, decimals_);
        token.mint(recipient, amount);

        vm.stopBroadcast();

        return address(token);
    }
}
