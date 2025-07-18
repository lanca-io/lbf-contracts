// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {IRebalancer} from "./interfaces/IRebalancer.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IOUToken} from "./IOUToken.sol";
import {PoolBase} from "../PoolBase/PoolBase.sol";

/**
 * @title Rebalancer
 * @notice Abstract contract for rebalancing pool liquidity
 */
abstract contract Rebalancer is IRebalancer, PoolBase {
     uint256 public constant BPS_DENOMINATOR = 10_000;
     uint256 public constant REBALANCER_PREMIUM_BPS = 10;

     IOUToken internal immutable i_iouToken;

     constructor(address iouToken) {
         i_iouToken = IOUToken(iouToken);
     }

     function fillDeficit(uint256 amount) external returns (uint256 iouAmount) {
         uint256 deficit = getCurrentDeficit();
         if (deficit == 0) revert NoDeficitToFill();

         // Cap the amount to the actual deficit
         if (amount > deficit) {
             amount = deficit;
         }

         // Transfer liquidity tokens from caller to the pool
         bool success = IERC20(getLiquidityToken()).transferFrom(msg.sender, address(this), amount);
         if (!success) revert TransferFailed();

         // Mint IOU tokens to the caller
         iouAmount = (amount * (BPS_DENOMINATOR + REBALANCER_PREMIUM_BPS)) / BPS_DENOMINATOR;
         i_iouToken.mint(msg.sender, iouAmount);

         emit DeficitFilled(amount, iouAmount);
         return iouAmount;
     }

     function takeSurplus(uint256 iouAmount) external returns (uint256 amount) {
         uint256 surplus = getCurrentSurplus();
         if (surplus == 0) revert NoSurplusToTake();

         // Calculate equivalent amount of surplus tokens
         amount = iouAmount;

         // Cap the amount to the actual surplus
         if (amount > surplus) {
             amount = surplus;
             iouAmount = amount;
         }

         // Burn IOU tokens from caller
         i_iouToken.burnFrom(msg.sender, iouAmount);

         // Transfer liquidity tokens to the caller
         bool success = IERC20(getLiquidityToken()).transfer(msg.sender, amount);
         if (!success) revert TransferFailed();

         emit SurplusTaken(amount, iouAmount);
         return amount;
     }

     function getIOUToken() external view returns (address) {
         return address(i_iouToken);
     }

 }
