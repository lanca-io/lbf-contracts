// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

interface IRebalancer {
    event DeficitFilled(address indexed rebalancer, uint256 liqTokenAmount);
    event SurplusTaken(address indexed rebalancer, uint256 liqTokenAmount, uint256 iouTokenAmount);
    event IOUBridged(
        bytes32 indexed messageId,
        address sender,
        uint24 dstChainSelector,
        uint256 amount
    );
    event IOUReceived(
        bytes32 indexed messageId,
        address receiver,
        uint24 srcChainSelector,
        uint256 amount
    );

    error NoDeficitToFill();
    error NoSurplusToTake();
    error InvalidDestinationChain();
    error ConceroSendFailed();
    error UnauthorizedSender();
    error GetMessageFeeFailed();
    error InsufficientRebalancingFee(uint256 totalRebalancingFee, uint256 rebalancerFee);

    /**
     * @notice Fills the deficit by providing liquidity token to the pool
     * @param amount Amount of liquidity token to provide
     */
    function fillDeficit(uint256 amount) external;

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
     * @return fee The fee amount in native token
     */
    function getBridgeIouNativeFee(uint24 dstChainSelector) external view returns (uint256 fee);
}
