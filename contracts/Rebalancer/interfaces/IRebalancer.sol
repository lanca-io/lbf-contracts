// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

interface IRebalancer {
    event DeficitFilled(uint256 amount, uint256 iouAmount);
    event SurplusTaken(uint256 amount, uint256 iouAmount);

    error NoDeficitToFill();
    error NoSurplusToTake();
    error TransferFailed();

    /**
     * @notice Fills the deficit by providing liquidity token to the pool
     * @param amount Amount of liquidity token to provide
     * @return iouAmount Amount of IOU tokens received
     */
    function fillDeficit(uint256 amount) external returns (uint256 iouAmount);

    /**
     * @notice Takes surplus from the pool by providing IOU tokens
     * @param iouAmount Amount of IOU tokens to provide for burning
     * @return amount Amount of liquidity token received
     */
    function takeSurplus(uint256 iouAmount) external returns (uint256 amount);

    /**
     * @notice Returns the address of the IOU token
     * @return iouToken Address of the IOU token
     */
    function getIOUToken() external view returns (address iouToken);
}
