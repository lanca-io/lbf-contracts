// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {ParentPoolHarness} from "../harnesses/ParentPoolHarness.sol";
import {DeployIOUToken} from "../scripts/deploy/DeployIOUToken.s.sol";
import {DeployLPToken} from "../scripts/deploy/DeployLPToken.s.sol";
import {DeployMockERC20, MockERC20} from "../scripts/deploy/DeployMockERC20.s.sol";
import {DeployParentPool} from "../scripts/deploy/DeployParentPool.s.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IOUToken} from "../../../contracts/Rebalancer/IOUToken.sol";
import {LPToken} from "../../../contracts/ParentPool/LPToken.sol";
import {LancaTest} from "../LancaTest.sol";
import {ParentPool} from "../../../contracts/ParentPool/ParentPool.sol";
import {IParentPool} from "../../../contracts/ParentPool/interfaces/IParentPool.sol";
import {Vm} from "forge-std/src/Vm.sol";
import {IPoolBase} from "../../../contracts/PoolBase/interfaces/IPoolBase.sol";

abstract contract ParentPoolBase is LancaTest {
    uint16 internal constant DEFAULT_TARGET_QUEUE_LENGTH = 5;
    uint32 internal constant NOW_TIMESTAMP = 1754300013;

    address internal s_childPool_1;
    address internal s_childPool_2;
    address internal s_childPool_3;
    address internal s_childPool_4;
    address internal s_childPool_5;

    uint24 internal constant childPoolChainSelector_1 = 1;
    uint24 internal constant childPoolChainSelector_2 = 2;
    uint24 internal constant childPoolChainSelector_3 = 3;
    uint24 internal constant childPoolChainSelector_4 = 4;
    uint24 internal constant childPoolChainSelector_5 = 5;

    ParentPoolHarness public s_parentPool;
    LPToken public lpToken;

    function setUp() public virtual {
        s_childPool_1 = makeAddr("childPool_1");
        s_childPool_2 = makeAddr("childPool_2");
        s_childPool_3 = makeAddr("childPool_3");
        s_childPool_4 = makeAddr("childPool_4");
        s_childPool_5 = makeAddr("childPool_5");

        DeployMockERC20 deployMockERC20 = new DeployMockERC20();
        usdc = IERC20(deployMockERC20.deployERC20("USD Coin", "USDC", 6));

        DeployIOUToken deployIOUToken = new DeployIOUToken();
        iouToken = deployIOUToken.deployIOUToken(deployer, address(0));

        DeployLPToken deployLPToken = new DeployLPToken();
        lpToken = LPToken(deployLPToken.deployLPToken(address(this), address(this)));

        DeployParentPool deployParentPool = new DeployParentPool();
        s_parentPool = ParentPoolHarness(
            payable(
                deployParentPool.deployParentPool(
                    address(usdc),
                    6,
                    address(lpToken),
                    conceroRouter,
                    PARENT_POOL_CHAIN_SELECTOR,
                    address(iouToken),
                    MIN_TARGET_BALANCE
                )
            )
        );

        lpToken.grantRole(lpToken.MINTER_ROLE(), address(s_parentPool));
        _fundTestAddresses();
        _approveUSDCForAll();
        _setQueuesLength();
        _setSupportedChildPools();
        _setLancaKeeper();
    }

    /* HELPER FUNCTIONS */

    function _fundTestAddresses() internal {
        vm.deal(user, 100 ether);
        vm.deal(liquidityProvider, 100 ether);
        vm.deal(operator, 100 ether);
        vm.deal(s_lancaKeeper, 10 ether);
        vm.deal(address(s_parentPool), 10 ether);

        vm.startPrank(deployer);
        MockERC20(address(usdc)).mint(user, 10_000_000e6);
        MockERC20(address(usdc)).mint(liquidityProvider, 50_000_000e6);
        MockERC20(address(usdc)).mint(operator, 1_000_000e6);
        vm.stopPrank();
    }

    function _approveUSDCForAll() internal {
        vm.prank(user);
        usdc.approve(address(s_parentPool), type(uint256).max);

        vm.prank(liquidityProvider);
        usdc.approve(address(s_parentPool), type(uint256).max);

        vm.prank(operator);
        usdc.approve(address(s_parentPool), type(uint256).max);
    }

    function _enterDepositQueue(address depositor, uint256 amount) internal returns (bytes32) {
        vm.prank(depositor);
        vm.recordLogs();
        s_parentPool.enterDepositQueue(amount);
        Vm.Log[] memory entries = vm.getRecordedLogs();
        return entries[entries.length - 1].topics[1];
    }

    function _enterWithdrawalQueue(address depositor, uint256 amount) internal returns (bytes32) {
        vm.prank(depositor);
        vm.recordLogs();
        s_parentPool.enterWithdrawQueue(amount);
        Vm.Log[] memory entries = vm.getRecordedLogs();
        return entries[entries.length - 1].topics[1];
    }

    function _setQueuesLength() internal {
        vm.startPrank(deployer);
        s_parentPool.setTargetDepositQueueLength(DEFAULT_TARGET_QUEUE_LENGTH);
        s_parentPool.setTargetWithdrawalQueueLength(DEFAULT_TARGET_QUEUE_LENGTH);
        vm.stopPrank();
    }

    function _fillDepositWithdrawalQueue(
        uint256 amountToDepositPerUser,
        uint256 amountToWithdrawPerUser
    ) internal returns (uint256, uint256) {
        uint256 totalDeposited;
        for (uint256 i; i < s_parentPool.getTargetDepositQueueLength(); ++i) {
            _enterDepositQueue(user, amountToDepositPerUser);
            totalDeposited += amountToDepositPerUser;
        }

        uint256 totalWithdraw;
        for (uint256 i; i < s_parentPool.getTargetWithdrawalQueueLength(); ++i) {
            _enterWithdrawalQueue(user, amountToWithdrawPerUser);
            totalWithdraw += amountToWithdrawPerUser;
        }

        return (totalDeposited, totalWithdraw);
    }

    function _setSupportedChildPools() internal {
        vm.startPrank(deployer);
        s_parentPool.setDstPool(childPoolChainSelector_1, s_childPool_1);
        s_parentPool.setDstPool(childPoolChainSelector_2, s_childPool_2);
        s_parentPool.setDstPool(childPoolChainSelector_3, s_childPool_3);
        s_parentPool.setDstPool(childPoolChainSelector_4, s_childPool_4);
        s_parentPool.setDstPool(childPoolChainSelector_5, s_childPool_5);
        vm.stopPrank();
    }

    function _setLancaKeeper() internal {
        vm.prank(deployer);
        s_parentPool.setLancaKeeper(s_lancaKeeper);
    }

    function _fillChildPoolSnapshots() internal {
        uint24[] memory childPoolChainSelectors = _getChildPoolsChainSelectors();

        for (uint256 i; i < childPoolChainSelectors.length; ++i) {
            s_parentPool.exposed_setChildPoolSnapshot(
                childPoolChainSelectors[i],
                IParentPool.SnapshotSubmission({
                    timestamp: NOW_TIMESTAMP,
                    balance: 0,
                    iouTotalReceived: 0,
                    iouTotalSent: 0,
                    iouTotalSupply: 0,
                    dailyFlow: IPoolBase.LiqTokenDailyFlow({inflow: 0, outflow: 0}),
                    totalLiqTokenSent: 0,
                    totalLiqTokenReceived: 0
                })
            );
        }
    }

    function _getChildPoolsChainSelectors() internal returns (uint24[] memory) {
        uint24[] memory childPoolChainSelectors = new uint24[](5);
        childPoolChainSelectors[0] = childPoolChainSelector_1;
        childPoolChainSelectors[1] = childPoolChainSelector_2;
        childPoolChainSelectors[2] = childPoolChainSelector_3;
        childPoolChainSelectors[3] = childPoolChainSelector_4;
        childPoolChainSelectors[4] = childPoolChainSelector_5;

        return childPoolChainSelectors;
    }

    /* MINT FUNCTIONS */

    function _mintUsdc(address receiver, uint256 amount) internal {
        vm.prank(deployer);
        MockERC20(address(usdc)).mint(receiver, amount);
    }
}
