// SPDX-License-Identifier: UNLICENSED
/* solhint-disable func-name-mixedcase */
pragma solidity 0.8.28;

import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {MessageCodec} from "@concero/v2-contracts/contracts/common/libraries/MessageCodec.sol";
import {IParentPool} from "contracts/ParentPool/interfaces/IParentPool.sol";

import {IBase} from "contracts/Base/interfaces/IBase.sol";
import {ChildPool} from "contracts/ChildPool/ChildPool.sol";
import {IOUToken} from "contracts/Rebalancer/IOUToken.sol";
import {ConceroRouterMockWithCall} from "../mocks/ConceroRouterMockWithCall.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {ParentPoolHarness} from "../harnesses/ParentPoolHarness.sol";
import {ParentPoolBase} from "./ParentPoolBase.sol";
import {BridgeCodec} from "contracts/common/libraries/BridgeCodec.sol";
import {Decimals} from "contracts/common/libraries/Decimals.sol";

contract DecimalsTest is ParentPoolBase {
    using BridgeCodec for address;

    ConceroRouterMockWithCall public s_conceroRouterMockWithCall;
    ChildPool public s_childPool;
    IOUToken public s_iouTokenChildPool;
    IERC20 public s_usdcWithDec18ChildPool;

    uint24 public constant CHILD_POOL_CHAIN_SELECTOR_1 = 333;
    uint8 public constant USDC_DEC_6 = 6;
    uint8 public constant USDC_DEC_18 = 18;
    uint256 public constant INITIAL_DEPOSIT = 33_333_333_333;
    uint256 public constant BRIDGE_AMOUNT = 3333333333000000000000;

    function setUp() public override {
        super.setUp();

        s_conceroRouterMockWithCall = new ConceroRouterMockWithCall();

        vm.startPrank(s_deployer);
        s_parentPool = new ParentPoolHarness(
            address(s_usdc),
            address(s_lpToken),
            address(s_iouToken),
            address(s_conceroRouterMockWithCall),
            PARENT_POOL_CHAIN_SELECTOR,
            MIN_TARGET_BALANCE
        );
        s_parentPool.initialize(s_deployer, s_lancaKeeper);

        s_lpToken.grantRole(s_lpToken.MINTER_ROLE(), address(s_parentPool));
        s_iouToken.grantRole(s_iouToken.MINTER_ROLE(), address(s_parentPool));

        s_usdcWithDec18ChildPool = new MockERC20("USD Coin", "USDC", USDC_DEC_18);
        s_iouTokenChildPool = new IOUToken(s_deployer, address(0), USDC_DEC_18);

        vm.label(address(s_usdcWithDec18ChildPool), "USDC-18");
        vm.label(address(s_iouTokenChildPool), "IOUToken-CP-18");

        s_childPool = new ChildPool(
            address(s_conceroRouterMockWithCall),
            address(s_iouTokenChildPool),
            address(s_usdcWithDec18ChildPool),
            CHILD_POOL_CHAIN_SELECTOR_1,
            PARENT_POOL_CHAIN_SELECTOR
        );
        s_childPool.initialize(s_deployer, s_lancaKeeper);

        s_parentPool.setDstPool(CHILD_POOL_CHAIN_SELECTOR_1, address(s_childPool).toBytes32());
        s_childPool.setDstPool(PARENT_POOL_CHAIN_SELECTOR, address(s_parentPool).toBytes32());
        s_childPool.grantRole(s_childPool.LANCA_KEEPER(), s_lancaKeeper);
        s_iouTokenChildPool.grantRole(s_iouTokenChildPool.MINTER_ROLE(), address(s_childPool));

        s_parentPool.setLiquidityCap(_addDecimals(1000000));
        vm.stopPrank();

        vm.prank(s_user);
        IERC20(address(s_usdcWithDec18ChildPool)).approve(address(s_childPool), type(uint256).max);

        vm.prank(s_liquidityProvider);
        IERC20(address(s_lpToken)).approve(address(s_parentPool), type(uint256).max);

        vm.startPrank(s_operator);
        IERC20(address(s_usdcWithDec18ChildPool)).approve(address(s_childPool), type(uint256).max);
        IERC20(address(s_iouTokenChildPool)).approve(address(s_childPool), type(uint256).max);
        IERC20(address(s_iouToken)).approve(address(s_parentPool), type(uint256).max);
        vm.stopPrank();

        vm.deal(address(s_parentPool), 100 ether);
        vm.deal(address(s_childPool), 100 ether);

        MockERC20(address(s_usdc)).mint(s_user, 1_000_000e6);
        MockERC20(address(s_usdcWithDec18ChildPool)).mint(
            s_operator,
            Decimals.toDecimals(INITIAL_DEPOSIT, USDC_DEC_6, USDC_DEC_18)
        );
        MockERC20(address(s_usdcWithDec18ChildPool)).mint(
            s_user,
            Decimals.toDecimals(BRIDGE_AMOUNT, USDC_DEC_6, USDC_DEC_18)
        );

        _approveUSDCForAll();
        _setLancaKeeper();
        _setTargetBalanceCalculationVars();
        _setMinDepositAmount(_addDecimals(100));
        _setMinWithdrawalAmount(_addDecimals(100));

        _setRelayerLib(address(s_childPool));
        _setValidatorLibs(address(s_childPool));
        _setRelayerLib(address(s_parentPool));
        _setValidatorLibs(address(s_parentPool));
    }

    function test_parentPool_overflow_POC() public {
        _initialDepositToParentPool();

        bytes memory dstChainData = MessageCodec.encodeEvmDstChainData(s_user, 0);

        s_conceroRouterMockWithCall.setSrcChainSelector(CHILD_POOL_CHAIN_SELECTOR_1);
        vm.prank(s_user);
        s_childPool.bridge{value: 0.0001 ether}(
            BRIDGE_AMOUNT,
            PARENT_POOL_CHAIN_SELECTOR,
            dstChainData,
            ""
        );
        vm.prank(s_user);
        s_childPool.bridge{value: 0.0001 ether}(
            BRIDGE_AMOUNT,
            PARENT_POOL_CHAIN_SELECTOR,
            dstChainData,
            ""
        );

        vm.prank(s_liquidityProvider);
        s_parentPool.enterWithdrawalQueue(33330000000);

        _sendSnapshotToParentPool();
        _triggerDepositWithdrawal();

        uint256 deficit = s_parentPool.getDeficit();
        vm.prank(s_operator);
        s_parentPool.fillDeficit(deficit);

        vm.prank(s_liquidityProvider);
        s_parentPool.enterDepositQueue(_addDecimals(111));

        _sendSnapshotToParentPool();

        // IParentPool.ChildPoolSnapshot memory snapshot = IParentPool.ChildPoolSnapshot({
        //     timestamp: uint32(block.timestamp),
        //     balance: 23327666665, // 23327666666
        //     iouTotalReceived: 0,
        //     iouTotalSent: 16665000000,
        //     iouTotalSupply: 0,
        //     dailyFlow: IBase.LiqTokenDailyFlow({inflow: 0, outflow: 0}),
        //     totalLiqTokenSent: 6661999999,
        //     totalLiqTokenReceived: 0
        // });

        // s_parentPool.exposed_setChildPoolSnapshot(CHILD_POOL_CHAIN_SELECTOR_1, snapshot);
        _triggerDepositWithdrawal();
    }

    function _initialDepositToParentPool() internal {
        vm.warp(block.timestamp + 1 days * 365);

        vm.prank(s_liquidityProvider);
        s_parentPool.enterDepositQueue(INITIAL_DEPOSIT);

        _sendSnapshotToParentPool();
        _triggerDepositWithdrawal();

        vm.startPrank(s_operator);
        s_childPool.fillDeficit(s_childPool.getDeficit());

        s_conceroRouterMockWithCall.setSrcChainSelector(CHILD_POOL_CHAIN_SELECTOR_1);
        s_childPool.bridgeIOU{value: 0.0001 ether}(
            BridgeCodec.toBytes32(s_operator),
            PARENT_POOL_CHAIN_SELECTOR,
            s_iouTokenChildPool.balanceOf(s_operator)
        );

        s_parentPool.takeSurplus(s_parentPool.getSurplus());
        vm.stopPrank();
    }

    function _sendSnapshotToParentPool() internal {
        s_conceroRouterMockWithCall.setSrcChainSelector(CHILD_POOL_CHAIN_SELECTOR_1);
        vm.prank(s_lancaKeeper);
        s_childPool.sendSnapshotToParentPool{value: 0.01 ether}();
    }

    function _triggerDepositWithdrawal() internal {
        s_conceroRouterMockWithCall.setSrcChainSelector(PARENT_POOL_CHAIN_SELECTOR);
        vm.prank(s_lancaKeeper);
        s_parentPool.triggerDepositWithdrawProcess();
    }
}
