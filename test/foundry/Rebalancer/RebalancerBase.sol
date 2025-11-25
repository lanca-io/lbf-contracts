// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {IConceroRouter} from "@concero/v2-contracts/contracts/interfaces/IConceroRouter.sol";
import {MessageCodec} from "@concero/v2-contracts/contracts/common/libraries/MessageCodec.sol";
import {ParentPoolHarness} from "../harnesses/ParentPoolHarness.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {IOUToken} from "../../../contracts/Rebalancer/IOUToken.sol";
import {LPToken} from "../../../contracts/ParentPool/LPToken.sol";
import {LancaTest} from "../helpers/LancaTest.sol";
import {ParentPool} from "../../../contracts/ParentPool/ParentPool.sol";
import {ChildPool} from "../../../contracts/ChildPool/ChildPool.sol";
import {IParentPool} from "../../../contracts/ParentPool/interfaces/IParentPool.sol";
import {Rebalancer} from "../../../contracts/Rebalancer/Rebalancer.sol";
import {Vm} from "forge-std/src/Vm.sol";
import {IBase} from "../../../contracts/Base/interfaces/IBase.sol";
import {ConceroRouterMockWithCall} from "../mocks/ConceroRouterMockWithCall.sol";
import {Base} from "../../../contracts/Base/Base.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {BridgeCodec} from "contracts/common/libraries/BridgeCodec.sol";

abstract contract RebalancerBase is LancaTest {
    using BridgeCodec for address;

    uint16 internal constant DEFAULT_TARGET_QUEUE_LENGTH = 5;
    uint32 internal constant NOW_TIMESTAMP = 1754300013;
    uint256 internal constant MAX_DEPOSIT_AMOUNT = 1_000_000_000e6;

    uint24 internal constant childPoolChainSelector_1 = 1;
    uint24 internal constant childPoolChainSelector_2 = 2;
    uint24 internal constant childPoolChainSelector_3 = 3;
    uint24 internal constant childPoolChainSelector_4 = 4;
    uint24 internal constant childPoolChainSelector_5 = 5;
    uint24 internal constant childPoolChainSelector_6 = 6;
    uint24 internal constant childPoolChainSelector_7 = 7;
    uint24 internal constant childPoolChainSelector_8 = 8;
    uint24 internal constant childPoolChainSelector_9 = 9;

    ParentPoolHarness public s_parentPool;
    LPToken public s_lpToken;
    address public s_conceroRouterWithCall = address(new ConceroRouterMockWithCall());
    ChildPool public s_childPool_1;
    ChildPool public s_childPool_2;
    ChildPool public s_childPool_3;
    ChildPool public s_childPool_4;
    ChildPool public s_childPool_5;
    ChildPool public s_childPool_6;
    ChildPool public s_childPool_7;
    ChildPool public s_childPool_8;
    ChildPool public s_childPool_9;

    ChildPool[] public s_childPools;

    function setUp() public virtual {
        vm.startPrank(s_deployer);
        s_iouToken = new IOUToken(address(this), address(0), USDC_TOKEN_DECIMALS);
        s_lpToken = new LPToken(address(this), address(this), USDC_TOKEN_DECIMALS);

        s_parentPool = new ParentPoolHarness(
            address(s_usdc),
            address(s_lpToken),
            address(s_iouToken),
            s_conceroRouterWithCall,
            PARENT_POOL_CHAIN_SELECTOR,
            MIN_TARGET_BALANCE
        );

        _deployChildPools();
        vm.stopPrank();

        s_lpToken.grantRole(s_lpToken.MINTER_ROLE(), address(s_parentPool));
        s_iouToken.grantRole(s_iouToken.MINTER_ROLE(), address(s_parentPool));
        _fundTestAddresses();
        _approveUSDCForAll();
        _setQueuesLength();
        _setLancaKeeper();
        _setTargetBalanceCalculationVars();
        _setMinDepositAmount(_addDecimals(100));
        _setLibs();
    }

    /* HELPER FUNCTIONS */

    function _deployChildPools() internal {
        s_childPool_1 = new ChildPool(
            s_conceroRouterWithCall,
            address(s_iouToken),
            address(s_usdc),
            childPoolChainSelector_1,
            PARENT_POOL_CHAIN_SELECTOR
        );
        s_childPool_2 = new ChildPool(
            s_conceroRouterWithCall,
            address(s_iouToken),
            address(s_usdc),
            childPoolChainSelector_2,
            PARENT_POOL_CHAIN_SELECTOR
        );
        s_childPool_3 = new ChildPool(
            s_conceroRouterWithCall,
            address(s_iouToken),
            address(s_usdc),
            childPoolChainSelector_3,
            PARENT_POOL_CHAIN_SELECTOR
        );
        s_childPool_4 = new ChildPool(
            s_conceroRouterWithCall,
            address(s_iouToken),
            address(s_usdc),
            childPoolChainSelector_4,
            PARENT_POOL_CHAIN_SELECTOR
        );
        s_childPool_5 = new ChildPool(
            s_conceroRouterWithCall,
            address(s_iouToken),
            address(s_usdc),
            childPoolChainSelector_5,
            PARENT_POOL_CHAIN_SELECTOR
        );
        s_childPool_6 = new ChildPool(
            s_conceroRouterWithCall,
            address(s_iouToken),
            address(s_usdc),
            childPoolChainSelector_6,
            PARENT_POOL_CHAIN_SELECTOR
        );
        s_childPool_7 = new ChildPool(
            s_conceroRouterWithCall,
            address(s_iouToken),
            address(s_usdc),
            childPoolChainSelector_7,
            PARENT_POOL_CHAIN_SELECTOR
        );
        s_childPool_8 = new ChildPool(
            s_conceroRouterWithCall,
            address(s_iouToken),
            address(s_usdc),
            childPoolChainSelector_8,
            PARENT_POOL_CHAIN_SELECTOR
        );
        s_childPool_9 = new ChildPool(
            s_conceroRouterWithCall,
            address(s_iouToken),
            address(s_usdc),
            childPoolChainSelector_9,
            PARENT_POOL_CHAIN_SELECTOR
        );

        s_childPools.push(s_childPool_1);
        s_childPools.push(s_childPool_2);
        s_childPools.push(s_childPool_3);
        s_childPools.push(s_childPool_4);
        s_childPools.push(s_childPool_5);
        s_childPools.push(s_childPool_6);
        s_childPools.push(s_childPool_7);
        s_childPools.push(s_childPool_8);
        s_childPools.push(s_childPool_9);

        vm.startPrank(s_deployer);
        s_childPool_1.setDstPool(PARENT_POOL_CHAIN_SELECTOR, address(s_parentPool).toBytes32());
        s_childPool_2.setDstPool(PARENT_POOL_CHAIN_SELECTOR, address(s_parentPool).toBytes32());
        s_childPool_3.setDstPool(PARENT_POOL_CHAIN_SELECTOR, address(s_parentPool).toBytes32());
        s_childPool_4.setDstPool(PARENT_POOL_CHAIN_SELECTOR, address(s_parentPool).toBytes32());
        s_childPool_5.setDstPool(PARENT_POOL_CHAIN_SELECTOR, address(s_parentPool).toBytes32());
        s_childPool_6.setDstPool(PARENT_POOL_CHAIN_SELECTOR, address(s_parentPool).toBytes32());
        s_childPool_7.setDstPool(PARENT_POOL_CHAIN_SELECTOR, address(s_parentPool).toBytes32());
        s_childPool_8.setDstPool(PARENT_POOL_CHAIN_SELECTOR, address(s_parentPool).toBytes32());
        s_childPool_9.setDstPool(PARENT_POOL_CHAIN_SELECTOR, address(s_parentPool).toBytes32());
        vm.stopPrank();

        _setRelayerLib(address(s_childPool_1));
        _setValidatorLibs(address(s_childPool_1));

        _setRelayerLib(address(s_childPool_2));
        _setValidatorLibs(address(s_childPool_2));

        _setRelayerLib(address(s_childPool_3));
        _setValidatorLibs(address(s_childPool_3));

        _setRelayerLib(address(s_childPool_4));
        _setValidatorLibs(address(s_childPool_4));

        _setRelayerLib(address(s_childPool_5));
        _setValidatorLibs(address(s_childPool_5));

        _setRelayerLib(address(s_childPool_6));
        _setValidatorLibs(address(s_childPool_6));

        _setRelayerLib(address(s_childPool_7));
        _setValidatorLibs(address(s_childPool_7));

        _setRelayerLib(address(s_childPool_8));
        _setValidatorLibs(address(s_childPool_8));

        _setRelayerLib(address(s_childPool_9));
        _setValidatorLibs(address(s_childPool_9));

        s_iouToken.grantRole(s_iouToken.MINTER_ROLE(), address(s_childPool_1));
        s_iouToken.grantRole(s_iouToken.MINTER_ROLE(), address(s_childPool_2));
        s_iouToken.grantRole(s_iouToken.MINTER_ROLE(), address(s_childPool_3));
        s_iouToken.grantRole(s_iouToken.MINTER_ROLE(), address(s_childPool_4));
        s_iouToken.grantRole(s_iouToken.MINTER_ROLE(), address(s_childPool_5));
        s_iouToken.grantRole(s_iouToken.MINTER_ROLE(), address(s_childPool_6));
        s_iouToken.grantRole(s_iouToken.MINTER_ROLE(), address(s_childPool_7));
        s_iouToken.grantRole(s_iouToken.MINTER_ROLE(), address(s_childPool_8));
        s_iouToken.grantRole(s_iouToken.MINTER_ROLE(), address(s_childPool_9));
    }

    function _fundTestAddresses() internal {
        vm.deal(s_user, 100 ether);
        vm.deal(s_liquidityProvider, 100 ether);
        vm.deal(s_operator, 100 ether);
        vm.deal(s_lancaKeeper, 10 ether);
        vm.deal(address(s_parentPool), 10 ether);

        vm.startPrank(s_deployer);
        MockERC20(address(s_usdc)).mint(s_user, 10_000_000e6);
        MockERC20(address(s_usdc)).mint(s_liquidityProvider, 50_000_000e6);
        MockERC20(address(s_usdc)).mint(s_operator, 1_000_000e6);
        vm.stopPrank();
    }

    function _approveUSDCForAll() internal {
        vm.prank(s_user);
        s_usdc.approve(address(s_parentPool), type(uint256).max);

        vm.prank(s_liquidityProvider);
        s_usdc.approve(address(s_parentPool), type(uint256).max);

        vm.prank(s_operator);
        s_usdc.approve(address(s_parentPool), type(uint256).max);
    }

    function _enterDepositQueue(address depositor, uint256 amount) internal returns (bytes32) {
        vm.startPrank(depositor);
        s_usdc.approve(address(s_parentPool), amount);
        vm.recordLogs();
        s_parentPool.enterDepositQueue(amount);
        vm.stopPrank();
        Vm.Log[] memory entries = vm.getRecordedLogs();
        return entries[entries.length - 1].topics[1];
    }

    function _enterWithdrawalQueue(address depositor, uint256 amount) internal returns (bytes32) {
        vm.startPrank(depositor);
        s_lpToken.approve(address(s_parentPool), amount);
        vm.recordLogs();
        s_parentPool.enterWithdrawalQueue(amount);
        vm.stopPrank();
        Vm.Log[] memory entries = vm.getRecordedLogs();
        return entries[entries.length - 1].topics[1];
    }

    function _setQueuesLength() internal {
        vm.startPrank(s_deployer);
        s_parentPool.setMinDepositQueueLength(DEFAULT_TARGET_QUEUE_LENGTH);
        s_parentPool.setMinWithdrawalQueueLength(DEFAULT_TARGET_QUEUE_LENGTH);
        vm.stopPrank();
    }

    function _setQueuesLength(uint16 depositQueueLength, uint16 withdrawalQueueLength) internal {
        vm.startPrank(s_deployer);
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
            _enterDepositQueue(s_user, amountToDepositPerUser);
            totalDeposited += amountToDepositPerUser;
        }

        uint256 totalWithdraw;
        for (uint256 i; i < s_parentPool.getMinWithdrawalQueueLength(); ++i) {
            _enterWithdrawalQueue(s_user, amountToWithdrawPerUser);
            totalWithdraw += amountToWithdrawPerUser;
        }

        return (totalDeposited, totalWithdraw);
    }

    function _setSupportedChildPools(uint256 amount) internal {
        /* solhint-disable gas-custom-errors */
        require(amount == 2 || amount == 4 || amount == 9, "Invalid supported child pools amount");

        vm.startPrank(s_deployer);
        if (amount == 2) {
            s_parentPool.setDstPool(childPoolChainSelector_1, address(s_childPool_1).toBytes32());
            s_parentPool.setDstPool(childPoolChainSelector_2, address(s_childPool_2).toBytes32());
        } else if (amount == 4) {
            s_parentPool.setDstPool(childPoolChainSelector_1, address(s_childPool_1).toBytes32());
            s_parentPool.setDstPool(childPoolChainSelector_2, address(s_childPool_2).toBytes32());
            s_parentPool.setDstPool(childPoolChainSelector_3, address(s_childPool_3).toBytes32());
            s_parentPool.setDstPool(childPoolChainSelector_4, address(s_childPool_4).toBytes32());
        } else if (amount == 9) {
            s_parentPool.setDstPool(childPoolChainSelector_1, address(s_childPool_1).toBytes32());
            s_parentPool.setDstPool(childPoolChainSelector_2, address(s_childPool_2).toBytes32());
            s_parentPool.setDstPool(childPoolChainSelector_3, address(s_childPool_3).toBytes32());
            s_parentPool.setDstPool(childPoolChainSelector_4, address(s_childPool_4).toBytes32());
            s_parentPool.setDstPool(childPoolChainSelector_5, address(s_childPool_5).toBytes32());
            s_parentPool.setDstPool(childPoolChainSelector_6, address(s_childPool_6).toBytes32());
            s_parentPool.setDstPool(childPoolChainSelector_7, address(s_childPool_7).toBytes32());
            s_parentPool.setDstPool(childPoolChainSelector_8, address(s_childPool_8).toBytes32());
            s_parentPool.setDstPool(childPoolChainSelector_9, address(s_childPool_9).toBytes32());
        }
        vm.stopPrank();
    }

    function _setLancaKeeper() internal {
        vm.prank(s_deployer);
        s_parentPool.setLancaKeeper(s_lancaKeeper);
    }

    function _setMinDepositAmount(uint256 amount) internal {
        vm.prank(s_deployer);
        s_parentPool.setMinDepositAmount(uint64(amount));
    }

    function _triggerDepositWithdrawProcess() internal {
        vm.prank(s_lancaKeeper);
        s_parentPool.triggerDepositWithdrawProcess();
    }

    function _processPendingWithdrawals() internal {
        vm.prank(s_lancaKeeper);
        s_parentPool.processPendingWithdrawals();
    }

    function _fillChildPoolSnapshots() internal {
        uint24[] memory childPoolChainSelectors = s_parentPool.getChildPoolChainSelectors();

        for (uint256 i; i < childPoolChainSelectors.length; i++) {
            uint256 balance = s_childPools[i].getTargetBalance();
            uint256 dailyInflow = s_childPools[i].getYesterdayFlow().inflow;
            uint256 dailyOutflow = s_childPools[i].getYesterdayFlow().outflow;

            s_parentPool.exposed_setChildPoolSnapshot(
                childPoolChainSelectors[i],
                _getChildPoolSnapshot(balance, dailyInflow, dailyOutflow)
            );
        }
    }

    function _fillChildPoolSnapshots(uint256 childPoolBalance) internal {
        uint24[] memory childPoolChainSelectors = s_parentPool.getChildPoolChainSelectors();

        for (uint256 i; i < childPoolChainSelectors.length; i++) {
            s_parentPool.exposed_setChildPoolSnapshot(
                childPoolChainSelectors[i],
                _getChildPoolSnapshot(childPoolBalance, 0, 0)
            );
        }
    }

    function _fillChildPoolSnapshots(
        uint256 childPoolBalance,
        uint256 dailyInflow,
        uint256 dailyOutflow
    ) internal {
        uint24[] memory childPoolChainSelectors = s_parentPool.getChildPoolChainSelectors();

        for (uint256 i; i < childPoolChainSelectors.length; i++) {
            s_parentPool.exposed_setChildPoolSnapshot(
                childPoolChainSelectors[i],
                _getChildPoolSnapshot(childPoolBalance, dailyInflow, dailyOutflow)
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

    function _getChildPoolsChainSelectors() internal pure returns (uint24[] memory) {
        uint24[] memory childPoolChainSelectors = new uint24[](4);
        childPoolChainSelectors[0] = childPoolChainSelector_1;
        childPoolChainSelectors[1] = childPoolChainSelector_2;
        childPoolChainSelectors[2] = childPoolChainSelector_3;
        childPoolChainSelectors[3] = childPoolChainSelector_4;

        return childPoolChainSelectors;
    }

    function _setTargetBalanceCalculationVars() internal {
        vm.startPrank(s_deployer);
        s_parentPool.setLurScoreSensitivity(uint64(5 * USDC_TOKEN_DECIMALS_SCALE));
        s_parentPool.setScoresWeights(
            uint64((7 * USDC_TOKEN_DECIMALS_SCALE) / 10),
            uint64((3 * USDC_TOKEN_DECIMALS_SCALE) / 10)
        );
        vm.stopPrank();
    }

    function _setupParentPoolWithBaseExample() internal {
        /*
               LBF state before target balances adjustments

               Pool  Balance  targetBalance  Outflow(24h)  Inflow(24h)
       			1     1k     	1k           	0k           0k
               	2     1k     	1k           	0k           0k
               	3     1k     	1k           	0k           0k
               	4     1k     	1k           	0k           0k
               	5     1k     	1k           	0k           0k
               	6     1k     	1k           	0k           0k
               	7     1k     	1k           	0k           0k
               	8     1k     	1k           	0k           0k
               	9     1k     	1k           	0k           0k
	(Parent)   10     1k     	1k           	0k           0k
        */

        uint256 defaultTargetBalance = 1_000 * USDC_TOKEN_DECIMALS_SCALE;
        uint24[] memory childPoolChainSelectors = s_parentPool.getChildPoolChainSelectors();

        for (uint256 i; i < childPoolChainSelectors.length; ++i) {
            s_parentPool.exposed_setChildPoolSnapshot(
                childPoolChainSelectors[i],
                _getChildPoolSnapshot(defaultTargetBalance, 0, 0)
            );
            s_parentPool.exposed_setChildPoolTargetBalance(
                childPoolChainSelectors[i],
                defaultTargetBalance
            );
        }
        s_parentPool.exposed_setTargetBalance(defaultTargetBalance);
        s_parentPool.exposed_setYesterdayFlow(0, 0);
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
                85_000 * USDC_TOKEN_DECIMALS_SCALE,
                140_000 * USDC_TOKEN_DECIMALS_SCALE,
                150_000 * USDC_TOKEN_DECIMALS_SCALE
            ],
            [
                95_000 * USDC_TOKEN_DECIMALS_SCALE,
                180_000 * USDC_TOKEN_DECIMALS_SCALE,
                200_000 * USDC_TOKEN_DECIMALS_SCALE
            ],
            [
                110_000 * USDC_TOKEN_DECIMALS_SCALE,
                50_000 * USDC_TOKEN_DECIMALS_SCALE,
                40_000 * USDC_TOKEN_DECIMALS_SCALE
            ],
            [
                90_000 * USDC_TOKEN_DECIMALS_SCALE,
                70_000 * USDC_TOKEN_DECIMALS_SCALE,
                90_000 * USDC_TOKEN_DECIMALS_SCALE
            ]
        ];
        uint256 defaultTargetBalance = 100_000 * USDC_TOKEN_DECIMALS_SCALE;

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
            60_000 * USDC_TOKEN_DECIMALS_SCALE,
            80_000 * USDC_TOKEN_DECIMALS_SCALE
        );
    }

    /* MINT FUNCTIONS */

    function _mintUsdc(address receiver, uint256 amount) internal {
        vm.prank(s_deployer);
        MockERC20(address(s_usdc)).mint(receiver, amount);
    }

    function _mintLpToken(address receiver, uint256 amount) internal {
        vm.prank(address(s_parentPool));
        s_lpToken.mint(receiver, amount);
    }

    function _takeRebalancerFee(uint256 amount) internal view returns (uint256) {
        return amount - s_parentPool.getRebalancerFee(amount);
    }

    function _takeWithdrawalFee(uint256 amount) internal view returns (uint256) {
        (uint256 conceroFee, uint256 rebalanceFee) = s_parentPool.getWithdrawalFee(amount);
        return amount - (conceroFee + rebalanceFee);
    }

    function _addDecimals(uint256 amount) internal pure returns (uint256) {
        return amount * USDC_TOKEN_DECIMALS_SCALE;
    }

    function _getUsers(uint256 amount) internal returns (address[] memory) {
        address[] memory users = new address[](amount);
        for (uint256 i; i < users.length; ++i) {
            users[i] = makeAddr(string(abi.encodePacked("user", Strings.toString(i + 1))));
        }
        return users;
    }

    function _getEmptyBalances(uint256 amount) internal pure returns (uint256[] memory) {
        uint256[] memory balances = new uint256[](amount);
        for (uint256 i; i < balances.length; ++i) {
            balances[i] = 0;
        }
        return balances;
    }

    function _takeSurplus(uint256 amount) internal {
        vm.startPrank(s_operator);
        s_iouToken.approve(address(s_parentPool), amount);
        s_parentPool.takeSurplus(amount);
        vm.stopPrank();
    }

    function _fillDeficit(uint256 amount) internal {
        vm.prank(s_operator);
        s_parentPool.fillDeficit(amount);
    }

    function _baseSetup() internal {
        vm.prank(s_deployer);
        s_parentPool.setLiquidityCap(_addDecimals(15_000));

        _setSupportedChildPools(9);
        _setQueuesLength(0, 0);
        _mintUsdc(address(s_parentPool), _addDecimals(1_000));
        _setupParentPoolWithBaseExample();
    }

    function _baseSetupWithLPMinting() internal {
        _baseSetup();

        address[] memory users = _getUsers(5);
        uint256 initialLpBalancePerUser = _takeRebalancerFee(_addDecimals(2_000));

        for (uint256 i; i < users.length; i++) {
            _mintLpToken(users[i], initialLpBalancePerUser);
            s_lpToken.approve(address(s_parentPool), type(uint256).max);
        }
    }

    function _setLibs() internal {
        _setRelayerLib(address(s_parentPool));
        _setValidatorLibs(address(s_parentPool));
    }

    function _topUpRebalancingFee(address pool, uint256 amount) internal {
        vm.startPrank(s_deployer);
        MockERC20(address(s_usdc)).mint(s_deployer, amount);
        MockERC20(address(s_usdc)).approve(pool, amount);
        Rebalancer(payable(pool)).topUpRebalancingFee(amount);
        vm.stopPrank();
    }
}
