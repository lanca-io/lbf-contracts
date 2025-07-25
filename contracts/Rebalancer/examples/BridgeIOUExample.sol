// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {IRebalancer} from "../interfaces/IRebalancer.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title BridgeIOUExample
 * @notice Example contract demonstrating cross-chain IOU bridging
 */
contract BridgeIOUExample {
    /**
     * @notice Example of bridging IOU tokens to another chain
     * @param rebalancer The rebalancer contract address
     * @param amount Amount of IOU tokens to bridge
     * @param dstChainSelector Destination chain selector
     */
    function bridgeIOUTokens(
        address rebalancer,
        uint256 amount,
        uint24 dstChainSelector
    ) external payable {
        IRebalancer rebalancerContract = IRebalancer(rebalancer);

        // Step 1: Check destination pool is configured
        address dstPool = rebalancerContract.dstPools(dstChainSelector);
        require(dstPool != address(0), "Destination pool not configured");

        // Step 2: Get the IOU token and approve rebalancer
        address iouToken = rebalancerContract.getIOUToken();
        IERC20(iouToken).approve(rebalancer, amount);

        // Step 3: Query the required message fee
        uint256 messageFee = rebalancerContract.getMessageFee(
            dstChainSelector,
            dstPool,
            300_000 // Default gas limit
        );
        require(msg.value >= messageFee, "Insufficient fee");

        // Step 4: Bridge the IOU tokens
        bytes32 messageId = rebalancerContract.bridgeIOU{value: messageFee}(
            amount,
            dstChainSelector
        );

        // Refund excess fee
        if (msg.value > messageFee) {
            (bool success, ) = msg.sender.call{value: msg.value - messageFee}("");
            require(success, "Refund failed");
        }

        // Log the bridge transaction
        emit IOUBridged(msg.sender, dstChainSelector, amount, messageId);
    }

    /**
     * @notice Example of configuring destination pools (admin only)
     * @param rebalancer The rebalancer contract address
     * @param chainSelectors Array of chain selectors
     * @param poolAddresses Array of pool addresses
     */
    function configureDstPools(
        address rebalancer,
        uint24[] calldata chainSelectors,
        address[] calldata poolAddresses
    ) external {
        require(chainSelectors.length == poolAddresses.length, "Length mismatch");

        IRebalancer rebalancerContract = IRebalancer(rebalancer);

        for (uint256 i = 0; i < chainSelectors.length; i++) {
            rebalancerContract.setDstPool(chainSelectors[i], poolAddresses[i]);
        }
    }

    //    /**
    //     * @notice Example workflow: Fill deficit on source chain and bridge IOU to destination
    //     * @param rebalancer The rebalancer contract address
    //     * @param deficitAmount Amount to fill deficit with
    //     * @param bridgeAmount Amount of IOU to bridge
    //     * @param dstChainSelector Destination chain selector
    //     */
    //    function fillDeficitAndBridge(
    //        address rebalancer,
    //        uint256 deficitAmount,
    //        uint256 bridgeAmount,
    //        uint24 dstChainSelector
    //    ) external payable {
    //        IRebalancer rebalancerContract = IRebalancer(rebalancer);
    //
    //        // Step 1: Fill deficit to receive IOU tokens
    //        address liquidityToken = rebalancerContract.getLiquidityToken();
    //        IERC20(liquidityToken).approve(rebalancer, deficitAmount);
    //
    //        uint256 iouReceived = rebalancerContract.fillDeficit(deficitAmount);
    //
    //        // Step 2: Bridge some or all of the received IOU tokens
    //        require(bridgeAmount <= iouReceived, "Bridge amount exceeds IOU received");
    //
    //        // Approve and bridge
    //        address iouToken = rebalancerContract.getIOUToken();
    //        IERC20(iouToken).approve(rebalancer, bridgeAmount);
    //
    //        // Get message fee
    //        address dstPool = rebalancerContract.dstPools(dstChainSelector);
    //        uint256 messageFee = rebalancerContract.getMessageFee(
    //            dstChainSelector,
    //            dstPool,
    //            300_000
    //        );
    //
    //        require(msg.value >= messageFee, "Insufficient fee for bridging");
    //
    //        // Bridge the tokens
    //        rebalancerContract.bridgeIOU{value: messageFee}(
    //            bridgeAmount,
    //            dstChainSelector
    //        );
    //    }

    event IOUBridged(
        address indexed sender,
        uint24 indexed dstChainSelector,
        uint256 amount,
        bytes32 messageId
    );
}

/**
 * @notice Example: Cross-chain IOU bridging flow
 *
 * Chain A (Source):
 * 1. User fills deficit and receives IOU tokens
 * 2. User calls bridgeIOU(amount, chainB_selector) with native gas for fees
 * 3. Rebalancer burns user's IOU tokens
 * 4. Rebalancer sends cross-chain message via ConceroRouter
 *
 * Chain B (Destination):
 * 1. ConceroRouter calls conceroReceive on destination Rebalancer
 * 2. Rebalancer validates the message came from authorized source pool
 * 3. Rebalancer decodes the message and mints IOU tokens to receiver
 * 4. Receiver can now use IOU tokens to take surplus on Chain B
 *
 * Security considerations:
 * - Only authorized pools can send/receive messages
 * - IOU tokens are burned on source before bridging
 * - Message fees must be paid in native token
 * - Admin must configure destination pools before bridging
 */
