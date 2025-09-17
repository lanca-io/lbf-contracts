// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {ICommonErrors} from "../common/interfaces/ICommonErrors.sol";
import {ConceroClient} from "@concero/v2-contracts/contracts/ConceroClient/ConceroClient.sol";
import {ConceroOwnable} from "../common/ConceroOwnable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IOUToken} from "../Rebalancer/IOUToken.sol";
import {IBase} from "./interfaces/IBase.sol";
import {CommonConstants} from "../common/CommonConstants.sol";
import {Storage as rs} from "../Rebalancer/libraries/Storage.sol";
import {Storage as s} from "./libraries/Storage.sol";

abstract contract Base is IBase, ConceroClient, ConceroOwnable {
    using s for s.Base;
    using s for rs.Rebalancer;

    uint32 private constant SECONDS_IN_DAY = 86400;

    address internal immutable i_liquidityToken;
    IOUToken internal immutable i_iouToken;
    uint8 internal immutable i_liquidityTokenDecimals;
    uint24 internal i_chainSelector;

    modifier onlyLancaKeeper() {
        s.Base storage s_base = s.base();
        require(
            msg.sender == s_base.lancaKeeper,
            ICommonErrors.UnauthorizedCaller(msg.sender, s_base.lancaKeeper)
        );

        _;
    }

    constructor(
        address liquidityToken,
        address conceroRouter,
        address iouToken,
        uint8 liquidityTokenDecimals,
        uint24 chainSelector
    ) ConceroClient(conceroRouter) {
        i_liquidityToken = liquidityToken;
        i_liquidityTokenDecimals = liquidityTokenDecimals;
        i_chainSelector = chainSelector;
        i_iouToken = IOUToken(iouToken);
    }

    receive() external payable {}

    /*   VIEW FUNCTIONS   */

    function getActiveBalance() public view virtual returns (uint256) {
        return
            IERC20(i_liquidityToken).balanceOf(address(this)) -
            rs.rebalancer().totalRebalancingFee -
            s.base().totalLancaFeeInLiqToken;
    }

    function getSurplus() public view returns (uint256) {
        uint256 activeBalance = getActiveBalance();
        uint256 targetBalance = getTargetBalance();

        if (activeBalance <= targetBalance) return 0;
        return activeBalance - targetBalance;
    }

    function getDeficit() public view returns (uint256 deficit) {
        uint256 targetBalance = getTargetBalance();
        uint256 activeBalance = getActiveBalance();
        deficit = activeBalance >= targetBalance ? 0 : targetBalance - activeBalance;
    }

    function getPoolData() external view returns (uint256 deficit, uint256 surplus) {
        deficit = getDeficit();
        surplus = getSurplus();
    }

    function setDstPool(uint24 chainSelector, address dstPool) public virtual onlyOwner {
        require(chainSelector != i_chainSelector, ICommonErrors.InvalidChainSelector());
        require(dstPool != address(0), ICommonErrors.AddressShouldNotBeZero());

        s.base().dstPools[chainSelector] = dstPool;
    }

    function getDstPool(uint24 chainSelector) public view returns (address) {
        return s.base().dstPools[chainSelector];
    }

    function getLancaKeeper() public view returns (address) {
        return s.base().lancaKeeper;
    }

    function getTargetBalance() public view returns (uint256) {
        return s.base().targetBalance;
    }

    function getYesterdayFlow() public view returns (LiqTokenDailyFlow memory) {
        return s.base().flowByDay[getYesterdayStartTimestamp()];
    }

    function getTodayStartTimestamp() public view returns (uint32) {
        return uint32(block.timestamp) / SECONDS_IN_DAY;
    }

    function getYesterdayStartTimestamp() public view returns (uint32) {
        return getTodayStartTimestamp() - 1;
    }

    function getLpFee(uint256 amount) public pure returns (uint256) {
        return (amount * CommonConstants.LP_PREMIUM_BPS) / CommonConstants.BPS_DENOMINATOR;
    }

    function getLancaFee(uint256 amount) public pure returns (uint256) {
        return
            (amount * (CommonConstants.LANCA_BRIDGE_PREMIUM_BPS)) / CommonConstants.BPS_DENOMINATOR;
    }

    function getRebalancerFee(uint256 amount) public pure returns (uint256) {
        return (amount * CommonConstants.REBALANCER_PREMIUM_BPS) / CommonConstants.BPS_DENOMINATOR;
    }

    /*   ADMIN FUNCTIONS   */

    function setLancaKeeper(address lancaKeeper) external onlyOwner {
        s.base().lancaKeeper = lancaKeeper;
    }

    //    function addDstPools(
    //        uint24[] calldata dstChainSelectors,
    //        address[] calldata dstPools
    //    ) external onlyOwner {
    //        require(dstChainSelectors.length > 0, ICommonErrors.EmptyArray());
    //        require(dstChainSelectors.length == dstPools.length, ICommonErrors.LengthMismatch());
    //
    //        s.Base storage s_base = s.base();
    //
    //        for (uint256 i = 0; i < dstChainSelectors.length; i++) {
    //            require(
    //                s_base.dstPools[dstChainSelectors[i]] == address(0),
    //                PoolAlreadyExists(dstChainSelectors[i])
    //            );
    //            s_base.dstPools[dstChainSelectors[i]] = dstPools[i];
    //        }
    //    }
    //
    //    function removeDstPools(uint24[] calldata dstChainSelectors) external onlyOwner {
    //        require(dstChainSelectors.length > 0, ICommonErrors.EmptyArray());
    //
    //        s.Base storage s_base = s.base();
    //
    //        for (uint256 i = 0; i < dstChainSelectors.length; i++) {
    //            s_base.dstPools[dstChainSelectors[i]] = address(0);
    //        }
    //    }

    /*   INTERNAL FUNCTIONS   */

    function _conceroReceive(
        bytes32 messageId,
        uint24 sourceChainSelector,
        bytes calldata sender,
        bytes calldata message
    ) internal override {
        s.Base storage s_base = s.base();

        require(
            s_base.dstPools[sourceChainSelector] == abi.decode(sender, (address)),
            ICommonErrors.UnauthorizedSender(
                abi.decode(sender, (address)),
                s_base.dstPools[sourceChainSelector]
            )
        );

        (ConceroMessageType messageType, bytes memory messageData) = abi.decode(
            message,
            (ConceroMessageType, bytes)
        );

        if (messageType == ConceroMessageType.BRIDGE_IOU) {
            _handleConceroReceiveBridgeIou(messageId, sourceChainSelector, messageData);
        } else if (messageType == ConceroMessageType.SEND_SNAPSHOT) {
            _handleConceroReceiveSnapshot(sourceChainSelector, messageData);
        } else if (messageType == ConceroMessageType.BRIDGE) {
            _handleConceroReceiveBridgeLiquidity(messageId, sourceChainSelector, messageData);
        } else if (messageType == ConceroMessageType.UPDATE_TARGET_BALANCE) {
            _handleConceroReceiveUpdateTargetBalance(messageData);
        } else {
            revert InvalidConceroMessageType();
        }
    }

    function _handleConceroReceiveBridgeIou(
        bytes32 messageId,
        uint24 sourceChainSelector,
        bytes memory messageData
    ) internal virtual;

    function _handleConceroReceiveSnapshot(
        uint24 sourceChainSelector,
        bytes memory messageData
    ) internal virtual;

    function _handleConceroReceiveBridgeLiquidity(
        bytes32 messageId,
        uint24 sourceChainSelector,
        bytes memory messageData
    ) internal virtual;

    function _handleConceroReceiveUpdateTargetBalance(bytes memory messageData) internal virtual;
}
