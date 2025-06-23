// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "./interfaces/IParentPool.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {PoolBase} from "../PoolBase/PoolBase.sol";
import {Storage as s} from "./libraries/Storage.sol";

contract ParentPool is IParentPool, PoolBase {
    using s for s.ParentPool;

    constructor(address liquidityToken, address lpToken) PoolBase(liquidityToken, lpToken) {}

    function enterDepositQueue(uint256 amount) external {
        IERC20(i_liquidityToken).transferFrom(msg.sender, address(this), amount);

        Deposit memory deposit = Deposit({liquidityTokenAmountToDeposit: amount, lp: msg.sender});
        bytes32 depositId = keccak256(
            abi.encodePacked(msg.sender, block.number, ++s.parentPool().depositNonce)
        );

        s.parentPool().depositsQueue[depositId] = deposit;
        s.parentPool().depositsQueueIds.push(depositId);

        emit DepositQueued(depositId, deposit.lp, amount);
    }

    function enterWithdrawQueue(uint256 amount) external {
        IERC20(i_lpToken).transferFrom(msg.sender, address(this), amount);

        Withdraw memory withdraw = Withdraw({lpTokenAmountToWithdraw: amount, lp: msg.sender});
        bytes32 withdrawId = keccak256(
            abi.encodePacked(msg.sender, block.number, ++s.parentPool().withdrawalNonce)
        );

        s.parentPool().withdrawalsQueue[withdrawId] = withdraw;
        s.parentPool().withdrawalsQueueIds.push(withdrawId);

        emit WithdrawQueued(withdrawId, withdraw.lp, amount);
    }
}
