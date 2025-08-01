// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

interface IRebalancer {
    event DeficitFilled(uint256 amount, uint256 iouAmount);
    event SurplusTaken(uint256 amount, uint256 iouAmount);
    event IOUBridged(
        address indexed sender,
        uint24 indexed dstChainSelector,
        uint256 amount,
        bytes32 messageId
    );
    event IOUReceived(
        bytes32 indexed messageId,
        uint24 srcChainSelector,
        address receiver,
        uint256 amount
    );

    error NoDeficitToFill();
    error NoSurplusToTake();
    error InvalidDestinationChain();
    error ConceroSendFailed();
    error UnauthorizedSender();
    error GetMessageFeeFailed();

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

    /**
     * @notice Bridges IOU tokens to another chain
     * @param amount Amount of IOU tokens to bridge
     * @param chainSelector Destination chain selector
     * @return messageId The ID of the cross-chain message
     */
    function bridgeIOU(
        uint256 amount,
        uint24 chainSelector
    ) external payable returns (bytes32 messageId);

    /**
     * @notice Gets the message fee for bridging to a destination chain
     * @param dstChainSelector Destination chain selector
     * @param dstPool Destination pool address
     * @param gasLimit Gas limit for the cross-chain message
     * @return fee The fee amount in native token
     */
    function getMessageFee(
        uint24 dstChainSelector,
        address dstPool,
        uint256 gasLimit
    ) external view returns (uint256 fee);
}
