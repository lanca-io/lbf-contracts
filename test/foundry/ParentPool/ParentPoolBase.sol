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
import {IBase} from "../../../contracts/Base/interfaces/IBase.sol";

abstract contract ParentPoolBase is LancaTest {
    uint16 internal constant DEFAULT_TARGET_QUEUE_LENGTH = 5;
    uint32 internal constant NOW_TIMESTAMP = 1754300013;
    uint256 internal constant MAX_DEPOSIT_AMOUNT = 1_000_000_000e6;

    address internal s_childPool_1;
    address internal s_childPool_2;
    address internal s_childPool_3;
    address internal s_childPool_4;

    uint24 internal constant childPoolChainSelector_1 = 1;
    uint24 internal constant childPoolChainSelector_2 = 2;
    uint24 internal constant childPoolChainSelector_3 = 3;
    uint24 internal constant childPoolChainSelector_4 = 4;

    ParentPoolHarness public s_parentPool;
    LPToken public lpToken;

    function setUp() public virtual {
        s_childPool_1 = makeAddr("childPool_1");
        s_childPool_2 = makeAddr("childPool_2");
        s_childPool_3 = makeAddr("childPool_3");
        s_childPool_4 = makeAddr("childPool_4");

        DeployMockERC20 deployMockERC20 = new DeployMockERC20();
        usdc = IERC20(deployMockERC20.deployERC20("USD Coin", "USDC", 6));

        DeployIOUToken deployIOUToken = new DeployIOUToken();
        iouToken = IOUToken(deployIOUToken.deployIOUToken(address(this), address(0)));

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
        iouToken.grantRole(iouToken.MINTER_ROLE(), address(s_parentPool));
        _fundTestAddresses();
        _approveUSDCForAll();
        _setQueuesLength();
        _setSupportedChildPools();
        _setLancaKeeper();
        _setTargetBalanceCalculationVars();
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
        vm.startPrank(depositor);
        usdc.approve(address(s_parentPool), amount);
        vm.recordLogs();
        s_parentPool.enterDepositQueue(amount);
        vm.stopPrank();
        Vm.Log[] memory entries = vm.getRecordedLogs();
        return entries[entries.length - 1].topics[1];
    }

    function _enterWithdrawalQueue(address depositor, uint256 amount) internal returns (bytes32) {
        vm.prank(depositor);
        vm.recordLogs();
        s_parentPool.enterWithdrawalQueue(amount);
        Vm.Log[] memory entries = vm.getRecordedLogs();
        return entries[entries.length - 1].topics[1];
    }

    function _setQueuesLength() internal {
        vm.startPrank(deployer);
        s_parentPool.setMinDepositQueueLength(DEFAULT_TARGET_QUEUE_LENGTH);
        s_parentPool.setMinWithdrawalQueueLength(DEFAULT_TARGET_QUEUE_LENGTH);
        vm.stopPrank();
    }

    function _setQueuesLength(uint16 depositQueueLength, uint16 withdrawalQueueLength) internal {
        vm.startPrank(deployer);
        s_parentPool.setMinDepositQueueLength(depositQueueLength);
        s_parentPool.setMinWithdrawalQueueLength(withdrawalQueueLength);
        vm.stopPrank();
    }

    function _fillDepositWithdrawalQueue(
        uint256 amountToDepositPerUser,
        uint256 amountToWithdrawPerUser
    ) internal returns (uint256, uint256) {
        uint256 totalDeposited;
        for (uint256 i; i < s_parentPool.getMinDepositQueueLength(); ++i) {
            _enterDepositQueue(user, amountToDepositPerUser);
            totalDeposited += amountToDepositPerUser;
        }

        uint256 totalWithdraw;
        for (uint256 i; i < s_parentPool.getMinWithdrawalQueueLength(); ++i) {
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
        vm.stopPrank();
    }

    function _setLancaKeeper() internal {
        vm.prank(deployer);
        s_parentPool.setLancaKeeper(s_lancaKeeper);
    }

    function _triggerDepositWithdrawProcess() internal {
        vm.prank(s_lancaKeeper);
        s_parentPool.triggerDepositWithdrawProcess();
    }

    function _fillChildPoolSnapshots() internal {
        uint24[] memory childPoolChainSelectors = _getChildPoolsChainSelectors();

        for (uint256 i; i < childPoolChainSelectors.length; ++i) {
            s_parentPool.exposed_setChildPoolSnapshot(
                childPoolChainSelectors[i],
                _getChildPoolSnapshot()
            );
        }
    }

    function _getChildPoolSnapshot(
        uint256 balance,
        uint256 dailyInflow,
        uint256 dailyOutflow
    ) internal pure returns (IParentPool.ChildPoolSnapshot memory) {
        IParentPool.ChildPoolSnapshot memory snapshot = _getChildPoolSnapshot();
        snapshot.balance = balance;
        snapshot.dailyFlow.inflow = dailyInflow;
        snapshot.dailyFlow.outflow = dailyOutflow;

        return snapshot;
    }

    function _getChildPoolSnapshot() internal pure returns (IParentPool.ChildPoolSnapshot memory) {
        return
            IParentPool.ChildPoolSnapshot({
                timestamp: NOW_TIMESTAMP,
                balance: 0,
                iouTotalReceived: 0,
                iouTotalSent: 0,
                iouTotalSupply: 0,
                dailyFlow: IBase.LiqTokenDailyFlow({inflow: 0, outflow: 0}),
                totalLiqTokenSent: 0,
                totalLiqTokenReceived: 0
            });
    }

    function _getChildPoolsChainSelectors() internal returns (uint24[] memory) {
        uint24[] memory childPoolChainSelectors = new uint24[](4);
        childPoolChainSelectors[0] = childPoolChainSelector_1;
        childPoolChainSelectors[1] = childPoolChainSelector_2;
        childPoolChainSelectors[2] = childPoolChainSelector_3;
        childPoolChainSelectors[3] = childPoolChainSelector_4;

        return childPoolChainSelectors;
    }

    function _setTargetBalanceCalculationVars() internal {
        vm.startPrank(deployer);
        s_parentPool.setLurScoreSensitivity(uint64(5 * LIQ_TOKEN_SCALE_FACTOR));
        s_parentPool.setScoresWeights(
            uint64((7 * LIQ_TOKEN_SCALE_FACTOR) / 10),
            uint64((3 * LIQ_TOKEN_SCALE_FACTOR) / 10)
        );
        vm.stopPrank();
    }

    function _setupParentPoolWithWhitePaperExample() internal {
        /*
               LBF state before target balances adjustments

               Pool  Balance  targetBalance  Outflow(24h)  Inflow(24h)
               A     120k     100k           80k           60k
               B     85k      100k           150k          140k
               C     95k      100k           200k          180k
               D     110k     100k           40k           50k
               E     90k      100k           90k           70k
        */
        uint256[3][4] memory childPoolsSetupData = [
            [
                85_000 * LIQ_TOKEN_SCALE_FACTOR,
                140_000 * LIQ_TOKEN_SCALE_FACTOR,
                150_000 * LIQ_TOKEN_SCALE_FACTOR
            ],
            [
                95_000 * LIQ_TOKEN_SCALE_FACTOR,
                180_000 * LIQ_TOKEN_SCALE_FACTOR,
                200_000 * LIQ_TOKEN_SCALE_FACTOR
            ],
            [
                110_000 * LIQ_TOKEN_SCALE_FACTOR,
                50_000 * LIQ_TOKEN_SCALE_FACTOR,
                40_000 * LIQ_TOKEN_SCALE_FACTOR
            ],
            [
                90_000 * LIQ_TOKEN_SCALE_FACTOR,
                70_000 * LIQ_TOKEN_SCALE_FACTOR,
                90_000 * LIQ_TOKEN_SCALE_FACTOR
            ]
        ];
        uint256 defaultTargetBalance = 100_000 * LIQ_TOKEN_SCALE_FACTOR;

        for (uint256 i; i < _getChildPoolsChainSelectors().length; ++i) {
            s_parentPool.exposed_setChildPoolSnapshot(
                _getChildPoolsChainSelectors()[i],
                _getChildPoolSnapshot(
                    childPoolsSetupData[i][0],
                    childPoolsSetupData[i][1],
                    childPoolsSetupData[i][2]
                )
            );
            s_parentPool.exposed_setChildPoolTargetBalance(
                _getChildPoolsChainSelectors()[i],
                defaultTargetBalance
            );
        }
        s_parentPool.exposed_setTargetBalance(defaultTargetBalance);
        s_parentPool.exposed_setYesterdayFlow(
            60_000 * LIQ_TOKEN_SCALE_FACTOR,
            80_000 * LIQ_TOKEN_SCALE_FACTOR
        );
    }

    /* MINT FUNCTIONS */

    function _mintUsdc(address receiver, uint256 amount) internal {
        vm.prank(deployer);
        MockERC20(address(usdc)).mint(receiver, amount);
    }

    function _mintLpToken(address receiver, uint256 amount) internal {
        vm.prank(address(s_parentPool));
        lpToken.mint(receiver, amount);
    }
}
