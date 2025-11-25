// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {IConceroRouter} from "@concero/v2-contracts/contracts/interfaces/IConceroRouter.sol";
import {MessageCodec} from "@concero/v2-contracts/contracts/common/libraries/MessageCodec.sol";
import {LancaTest} from "../helpers/LancaTest.sol";
import {IBase} from "contracts/Base/interfaces/IBase.sol";
import {ChildPool} from "contracts/ChildPool/ChildPool.sol";
import {ParentPool} from "contracts/ParentPool/ParentPool.sol";
import {LPToken} from "contracts/ParentPool/LPToken.sol";
import {IOUToken} from "contracts/Rebalancer/IOUToken.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {BridgeCodec} from "contracts/common/libraries/BridgeCodec.sol";

abstract contract LancaBridgeBase is LancaTest {
    using BridgeCodec for address;
    using MessageCodec for IConceroRouter.MessageRequest;

    ChildPool public s_childPool;
    ParentPool public s_parentPool;
    LPToken public s_lpToken = new LPToken(address(this), address(this), USDC_TOKEN_DECIMALS);

    function setUp() public virtual {
        vm.startPrank(s_deployer);
        s_childPool = new ChildPool(
            address(s_conceroRouter),
            address(s_18DecIouToken),
            address(s_18DecUsdc),
            CHILD_POOL_CHAIN_SELECTOR,
            PARENT_POOL_CHAIN_SELECTOR
        );

        s_parentPool = new ParentPool(
            address(s_usdc),
            address(s_lpToken),
            address(s_iouToken),
            s_conceroRouter,
            PARENT_POOL_CHAIN_SELECTOR,
            MIN_TARGET_BALANCE
        );
        vm.stopPrank();

        _addDstPools();
        _fundTestAddresses();
        _approveUSDCForAll();
        _setLibs();

        // For correct getYesterdayFlow calculation
        vm.warp(block.timestamp + 1 days * 365);
    }

    function _addDstPools() internal {
        vm.startPrank(s_deployer);
        s_childPool.setDstPool(PARENT_POOL_CHAIN_SELECTOR, address(s_parentPool).toBytes32());
        s_parentPool.setDstPool(CHILD_POOL_CHAIN_SELECTOR, address(s_childPool).toBytes32());
        vm.stopPrank();
    }

    function _fundTestAddresses() internal {
        vm.deal(s_user, 100 ether);
        vm.deal(s_liquidityProvider, 100 ether);
        vm.deal(s_operator, 100 ether);

        vm.startPrank(s_deployer);
        MockERC20(address(s_usdc)).mint(s_user, 10_000_000e6);
        MockERC20(address(s_usdc)).mint(s_liquidityProvider, 50_000_000e6);
        MockERC20(address(s_usdc)).mint(s_operator, 1_000_000e6);
        //        MockERC20(address(s_usdc)).mint(address(s_childPool), INITIAL_POOL_LIQUIDITY);
        vm.stopPrank();

        deal(address(s_18DecUsdc), address(s_childPool), 1_000_000 * (10 ** STD_TOKEN_DECIMALS));
        deal(address(s_18DecUsdc), s_user, 1_000_000 * (10 ** STD_TOKEN_DECIMALS));
    }

    function _approveUSDCForAll() internal {
        vm.prank(s_user);
        IERC20(s_usdc).approve(address(s_childPool), type(uint256).max);

        vm.prank(s_liquidityProvider);
        IERC20(s_usdc).approve(address(s_childPool), type(uint256).max);

        vm.prank(s_operator);
        IERC20(s_usdc).approve(address(s_childPool), type(uint256).max);

        vm.prank(s_user);
        IERC20(s_usdc).approve(address(s_parentPool), type(uint256).max);

        vm.prank(s_user);
        IERC20(s_18DecUsdc).approve(address(s_childPool), type(uint256).max);

        vm.prank(s_liquidityProvider);
        IERC20(s_usdc).approve(address(s_parentPool), type(uint256).max);

        vm.prank(s_operator);
        IERC20(s_usdc).approve(address(s_parentPool), type(uint256).max);
    }

    function _setLibs() internal {
        _setRelayerLib(address(s_parentPool));
        _setValidatorLibs(address(s_parentPool));
        _setRelayerLib(address(s_childPool));
        _setValidatorLibs(address(s_childPool));
    }

    function _receiveBridge(
        address pool,
        uint256 amount,
        address receiver,
        uint32 dstChainGasLimit
    ) internal {
        IConceroRouter.MessageRequest memory messageRequest = _buildMessageRequest(
            BridgeCodec.encodeBridgeData(
                s_user,
                amount,
                USDC_TOKEN_DECIMALS,
                MessageCodec.encodeEvmDstChainData(receiver, dstChainGasLimit),
                ""
            ),
            PARENT_POOL_CHAIN_SELECTOR,
            address(s_parentPool)
        );

        vm.prank(s_conceroRouter);
        s_parentPool.conceroReceive(
            messageRequest.toMessageReceiptBytes(
                CHILD_POOL_CHAIN_SELECTOR,
                address(s_childPool),
                NONCE
            ),
            s_validationChecks,
            s_validatorLibs,
            s_relayerLib
        );
    }
}
