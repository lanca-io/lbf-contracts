// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {ParentPoolHarness} from "../harnesses/ParentPoolHarness.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {IOUToken} from "../../../contracts/Rebalancer/IOUToken.sol";
import {LPToken} from "../../../contracts/ParentPool/LPToken.sol";
import {LancaTest} from "../helpers/LancaTest.sol";
import {ParentPool} from "../../../contracts/ParentPool/ParentPool.sol";
import {IParentPool} from "../../../contracts/ParentPool/interfaces/IParentPool.sol";
import {IBase} from "../../../contracts/Base/interfaces/IBase.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {Vm} from "forge-std/src/Vm.sol";
import {BridgeCodec} from "contracts/common/libraries/BridgeCodec.sol";
import {Decimals} from "contracts/common/libraries/Decimals.sol";

abstract contract ParentPoolBase is LancaTest {
    using BridgeCodec for address;

    uint16 internal constant DEFAULT_TARGET_QUEUE_LENGTH = 5;
    uint32 internal constant NOW_TIMESTAMP = 1754300013;
    uint256 internal constant MAX_DEPOSIT_AMOUNT = 1_000_000_000e6;

    address internal s_childPool_1 = makeAddr("childPool_1");
    address internal s_childPool_2 = makeAddr("childPool_2");
    address internal s_childPool_3 = makeAddr("childPool_3");
    address internal s_childPool_4 = makeAddr("childPool_4");

    uint24 internal constant childPoolChainSelector_1 = 1;
    uint24 internal constant childPoolChainSelector_2 = 2;
    uint24 internal constant childPoolChainSelector_3 = 3;
    uint24 internal constant childPoolChainSelector_4 = 4;

    ParentPoolHarness public s_parentPool;
    LPToken public s_lpToken;

    function setUp() public virtual {
        vm.startPrank(s_deployer);
        s_iouToken = new IOUToken(s_deployer, address(this), USDC_TOKEN_DECIMALS);
        s_lpToken = new LPToken(s_deployer, address(this), USDC_TOKEN_DECIMALS);
        s_parentPool = new ParentPoolHarness(
            address(s_usdc),
            address(s_lpToken),
            address(s_iouToken),
            s_conceroRouter,
            PARENT_POOL_CHAIN_SELECTOR,
            MIN_TARGET_BALANCE
        );
        s_parentPool.initialize(s_deployer, s_lancaKeeper);

        s_lpToken.grantRole(s_lpToken.MINTER_ROLE(), address(s_parentPool));
        s_iouToken.grantRole(s_iouToken.MINTER_ROLE(), address(s_parentPool));
        vm.stopPrank();

        _fundTestAddresses();
        _approveUSDCForAll();
        _setQueuesLength();
        _setSupportedChildPools();
        _setLancaKeeper();
        _setTargetBalanceCalculationVars();
        _setMinDepositAmount(_addDecimals(100));
        _setMinWithdrawalAmount(_addDecimals(100));
        _setLibs();
        _setFeeBps();
    }

    /* HELPER FUNCTIONS */

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

    function _setSupportedChildPools() internal {
        vm.startPrank(s_deployer);
        s_parentPool.setDstPool(childPoolChainSelector_1, s_childPool_1.toBytes32());
        s_parentPool.setDstPool(childPoolChainSelector_2, s_childPool_2.toBytes32());
        s_parentPool.setDstPool(childPoolChainSelector_3, s_childPool_3.toBytes32());
        s_parentPool.setDstPool(childPoolChainSelector_4, s_childPool_4.toBytes32());
        vm.stopPrank();
    }

    function _setSupportedChildPools(uint256 poolAmount) internal {
        uint24[] memory childPoolChainSelectors = s_parentPool.getChildPoolChainSelectors();

        vm.startPrank(s_deployer);
        for (uint24 i = uint24(childPoolChainSelectors.length + 1); i <= poolAmount; i++) {
            string memory prefix = "childPool_";
            string memory poolName = string(abi.encodePacked(prefix, Strings.toString(i)));
            s_parentPool.setDstPool(i, makeAddr(poolName).toBytes32());
        }
        vm.stopPrank();
    }

    function _setLancaKeeper() internal {
        vm.startPrank(s_deployer);
        s_parentPool.grantRole(s_parentPool.LANCA_KEEPER(), s_lancaKeeper);
        vm.stopPrank();
    }

    function _setMinDepositAmount(uint256 amount) internal {
        vm.prank(s_deployer);
        s_parentPool.setMinDepositAmount(uint64(amount));
    }

    function _setMinWithdrawalAmount(uint256 amount) internal {
        vm.prank(s_deployer);
        s_parentPool.setMinWithdrawalAmount(uint64(amount));
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

        for (uint256 i; i < childPoolChainSelectors.length; ++i) {
            s_parentPool.exposed_setChildPoolSnapshot(
                childPoolChainSelectors[i],
                _getChildPoolSnapshot()
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
        snapshot.balance = Decimals.toDecimals(balance, USDC_TOKEN_DECIMALS, SCALE_TOKEN_DECIMALS);
        snapshot.dailyFlow.inflow = Decimals.toDecimals(
            dailyInflow,
            USDC_TOKEN_DECIMALS,
            SCALE_TOKEN_DECIMALS
        );
        snapshot.dailyFlow.outflow = Decimals.toDecimals(
            dailyOutflow,
            USDC_TOKEN_DECIMALS,
            SCALE_TOKEN_DECIMALS
        );

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

    function _setFeeBps() internal {
        vm.startPrank(s_deployer);

        s_parentPool.setRebalancerFeeBps(REBALANCER_FEE_BPS); // 1bps
        s_parentPool.setLancaBridgeFeeBps(LANCA_BRIDGE_FEE_BPS); // 5bps
        s_parentPool.setLpFeeBps(LP_FEE_BPS); // 1bps

        vm.stopPrank();
    }
}
