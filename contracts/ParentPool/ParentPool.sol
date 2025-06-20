// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {PoolBase} from "../PoolBase/PoolBase.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract ParentPool is PoolBase {
    function enterDepositQueue(uint256 amount) external {
        IERC20(i_liquidityToken).transferFrom(msg.sender, address(this), amount);
    }
}
