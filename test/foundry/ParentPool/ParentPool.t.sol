// SPDX-License-Identifier: UNLICENSED
/* solhint-disable func-name-mixedcase */
pragma solidity 0.8.28;

import {IConceroRouter} from "@concero/v2-contracts/contracts/interfaces/IConceroRouter.sol";
import {MessageCodec} from "@concero/v2-contracts/contracts/common/libraries/MessageCodec.sol";
import {BridgeCodec} from "contracts/common/libraries/BridgeCodec.sol";
import {ICommonErrors} from "contracts/common/interfaces/ICommonErrors.sol";
import {ILancaKeeper} from "contracts/ParentPool/interfaces/ILancaKeeper.sol";
import {IBase} from "contracts/Base/interfaces/IBase.sol";
import {ParentPool, IParentPool, ParentPoolBase, LPToken} from "./ParentPoolBase.sol";
import {Base} from "contracts/Base/Base.sol";

import {MockERC20} from "../mocks/MockERC20.sol";

contract ParentPoolTest is ParentPoolBase {
    using MessageCodec for IConceroRouter.MessageRequest;
    using BridgeCodec for address;

    function setUp() public override {
        super.setUp();
        vm.warp(NOW_TIMESTAMP);
    }

    function test_constructor_RevertsInvalidLiqTokenDecimals() public {
        uint8 invalidLiqTokenDecimals = 5;
        MockERC20 lpToken = new MockERC20("MockLPToken", "MLP", invalidLiqTokenDecimals);

        vm.expectRevert(Base.InvalidLiqTokenDecimals.selector);
        new ParentPool(
            address(s_usdc),
            address(lpToken),
            address(s_iouToken),
            s_conceroRouter,
            PARENT_POOL_CHAIN_SELECTOR,
            MIN_TARGET_BALANCE
        );
    }

    /** -- Enter Deposit Queue -- */

    function test_enterDepositQueue_RevertsMinDepositAmountNotSet() public {
        vm.prank(s_deployer);
        s_parentPool.setMinDepositAmount(0);

        vm.expectRevert(ICommonErrors.MinDepositAmountNotSet.selector);
        s_parentPool.enterDepositQueue(100);
    }

    function test_enterDepositQueue_RevertsDepositAmountIsTooLow() public {
        vm.prank(s_deployer);
        s_parentPool.setMinDepositAmount(100);

        vm.expectRevert(
            abi.encodeWithSelector(ICommonErrors.DepositAmountIsTooLow.selector, 99, 100)
        );
        s_parentPool.enterDepositQueue(99);
    }

    function test_enterDepositQueue_RevertsDepositQueueIsFull() public {
        for (uint256 i; i < 250; i++) {
            _enterDepositQueue(s_user, _addDecimals(100));
        }

        vm.expectRevert(IParentPool.DepositQueueIsFull.selector);

        vm.prank(s_user);
        s_parentPool.enterDepositQueue(_addDecimals(100));
    }

    function test_enterDepositQueue_LiquidityCapReached() public {
        _baseSetup();

        uint256 newLiquidityCap = _addDecimals(100);
        _enterDepositQueue(s_user, newLiquidityCap);

        _triggerDepositWithdrawProcess();

        vm.prank(s_deployer);
        s_parentPool.setLiquidityCap(newLiquidityCap);

        vm.expectRevert(
            abi.encodeWithSelector(IParentPool.LiquidityCapReached.selector, newLiquidityCap)
        );
        vm.prank(s_user);
        s_parentPool.enterDepositQueue(newLiquidityCap + 1);
    }

    function test_enterDepositQueue_EmitsDepositQueued() public {
        _baseSetup();

        bytes32 depositId = keccak256(abi.encodePacked(s_user, block.number, uint256(1)));

        vm.expectEmit(true, true, true, true);
        emit IParentPool.DepositQueued(depositId, s_user, _addDecimals(100));

        vm.prank(s_user);
        s_parentPool.enterDepositQueue(_addDecimals(100));
    }

    /** -- Enter Withdrawal Queue -- */

    function test_enterWithdrawalQueue_RevertsMinWithdrawalAmountNotSet() public {
        vm.prank(s_deployer);
        s_parentPool.setMinWithdrawalAmount(0);

        vm.expectRevert(ICommonErrors.MinWithdrawalAmountNotSet.selector);
        s_parentPool.enterWithdrawalQueue(_addDecimals(100));
    }

    function test_enterWithdrawalQueue_RevertsWithdrawalAmountIsTooLow() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                ICommonErrors.WithdrawalAmountIsTooLow.selector,
                0,
                _addDecimals(100)
            )
        );

        s_parentPool.enterWithdrawalQueue(0);
    }

    function test_enterWithdrawalQueue_RevertsWithdrawalQueueIsFull() public {
        _setQueuesLength(0, 0);
        _enterDepositQueue(s_user, _addDecimals(100_000));

        _fillChildPoolSnapshots();
        _triggerDepositWithdrawProcess();

        for (uint256 i; i < 250; i++) {
            _enterWithdrawalQueue(s_user, _addDecimals(100));
        }

        vm.expectRevert(IParentPool.WithdrawalQueueIsFull.selector);

        vm.prank(s_user);
        s_parentPool.enterWithdrawalQueue(_addDecimals(100));
    }

    function test_enterWithdrawalQueue_EmitsWithdrawalQueued() public {
        _baseSetup();
        _mintLpToken(s_user, _addDecimals(100));

        vm.prank(s_user);
        s_lpToken.approve(address(s_parentPool), _addDecimals(100));

        bytes32 withdrawalId = keccak256(abi.encodePacked(s_user, block.number, uint256(1)));

        vm.expectEmit(true, true, true, true);
        emit IParentPool.WithdrawalQueued(withdrawalId, s_user, _addDecimals(100));

        vm.prank(s_user);
        s_parentPool.enterWithdrawalQueue(_addDecimals(100));
    }

    /** -- Trigger Deposit Withdraw Process -- */

    function test_triggerDepositWithdrawProcess_RevertsQueuesAreNotFull() public {
        vm.expectRevert(IParentPool.QueuesAreNotFull.selector);

        vm.prank(s_lancaKeeper);
        s_parentPool.triggerDepositWithdrawProcess();
    }

    function test_triggerDepositWithdrawProcess_RevertsChildPoolSnapshotsAreNotReady() public {
        _setQueuesLength(0, 0);
        _enterDepositQueue(s_user, _addDecimals(100));

        vm.expectRevert(IParentPool.ChildPoolSnapshotsAreNotReady.selector);

        vm.prank(s_lancaKeeper);
        s_parentPool.triggerDepositWithdrawProcess();
    }

    function test_triggerDepositWithdrawProcess_RevertsInvalidDstChainSelector() public {
        _setQueuesLength(0, 0);
        _enterDepositQueue(s_user, _addDecimals(100));

        uint24 invalidChainSelector = 1;
        s_parentPool.exposed_setDstPool(invalidChainSelector, bytes32(0));

        _fillChildPoolSnapshots();

        vm.expectRevert(
            abi.encodeWithSelector(
                ICommonErrors.InvalidDstChainSelector.selector,
                invalidChainSelector
            )
        );

        vm.prank(s_lancaKeeper);
        s_parentPool.triggerDepositWithdrawProcess();
    }

    /** -- Process Pending Withdrawals -- */

    function test_processPendingWithdrawals_RevertsPendingWithdrawalsAreNotReady() public {
        vm.expectRevert(
            abi.encodeWithSelector(ILancaKeeper.PendingWithdrawalsAreNotReady.selector, 0, 0)
        );

        vm.prank(s_lancaKeeper);
        s_parentPool.processPendingWithdrawals();

        _baseSetupWithLPMinting();

        address user1 = _getUsers(1)[0];
        _enterWithdrawalQueue(user1, _takeRebalancerFee(_addDecimals(2_000)));

        _fillChildPoolSnapshots(_addDecimals(1000));
        _triggerDepositWithdrawProcess();

        vm.expectRevert(
            abi.encodeWithSelector(
                ILancaKeeper.PendingWithdrawalsAreNotReady.selector,
                _addDecimals(1800),
                _addDecimals(200)
            )
        );

        vm.prank(s_lancaKeeper);
        s_parentPool.processPendingWithdrawals();
    }

    /** -- Setters -- */

    function test_setAverageConceroMessageFee() public {
        _baseSetupWithLPMinting();

        vm.prank(s_deployer);
        s_parentPool.setAverageConceroMessageFee(uint96(_addDecimals(1)));

        address user1 = _getUsers(1)[0];
        _enterWithdrawalQueue(user1, _takeRebalancerFee(_addDecimals(2_000)));

        _fillChildPoolSnapshots();
        _triggerDepositWithdrawProcess();

        (uint256 conceroFee, uint256 rebalanceFee) = s_parentPool.getWithdrawalFee(
            _addDecimals(2_000)
        );
        assertEq(conceroFee, _addDecimals(36));
        assertEq(rebalanceFee, s_parentPool.getRebalancerFee(_addDecimals(2_000)));
    }

    function test_setDstPool_ReversInvalidChainSelector() public {
        vm.expectRevert(ICommonErrors.AddressShouldNotBeZero.selector);

        vm.prank(s_deployer);
        s_parentPool.setDstPool(1, address(0).toBytes32());

        vm.expectRevert(ICommonErrors.InvalidChainSelector.selector);

        vm.prank(s_deployer);
        s_parentPool.setDstPool(1, address(1).toBytes32());
    }

    function test_setLurScoreSensitivity_RevertsInvalidLurScoreSensitivity() public {
        vm.expectRevert(IParentPool.InvalidLurScoreSensitivity.selector);

        vm.prank(s_deployer);
        s_parentPool.setLurScoreSensitivity(0);

        // Should be from 1.1 * LIQ_TOKEN_SCALE_FACTOR to 9.9 * LIQ_TOKEN_SCALE_FACTOR

        vm.expectRevert(IParentPool.InvalidLurScoreSensitivity.selector);

        vm.prank(s_deployer);
        s_parentPool.setLurScoreSensitivity(uint64(_addDecimals(1)));

        vm.expectRevert(IParentPool.InvalidLurScoreSensitivity.selector);

        vm.prank(s_deployer);
        s_parentPool.setLurScoreSensitivity(uint64(_addDecimals(10)));
    }

    function test_setScoresWeights_RevertsInvalidScoresWeights() public {
        vm.expectRevert(IParentPool.InvalidScoreWeights.selector);

        vm.prank(s_deployer);
        s_parentPool.setScoresWeights(0, 0);

        // Total weight should be 100% (1 * LIQ_TOKEN_SCALE_FACTOR)

        vm.expectRevert(IParentPool.InvalidScoreWeights.selector);

        vm.prank(s_deployer);
        s_parentPool.setScoresWeights(1, 1);

        vm.expectRevert(IParentPool.InvalidScoreWeights.selector);

        vm.prank(s_deployer);
        s_parentPool.setScoresWeights(uint64(_addDecimals(1)), 1);
    }

    /** -- Getters -- */

    function test_getChildPoolChainSelectors() public view {
        uint24[] memory childPoolChainSelectors = s_parentPool.getChildPoolChainSelectors();

        assertEq(childPoolChainSelectors.length, 4);
        assertEq(childPoolChainSelectors[0], childPoolChainSelector_1);
        assertEq(childPoolChainSelectors[1], childPoolChainSelector_2);
        assertEq(childPoolChainSelectors[2], childPoolChainSelector_3);
        assertEq(childPoolChainSelectors[3], childPoolChainSelector_4);
    }

    function test_isReadyToTriggerDepositWithdrawProcess() public {
        assertEq(s_parentPool.isReadyToTriggerDepositWithdrawProcess(), false);

        _baseSetup();
        _enterDepositQueue(s_user, _addDecimals(100));
        _fillChildPoolSnapshots();

        assertEq(s_parentPool.isReadyToTriggerDepositWithdrawProcess(), true);
    }

    function test_areQueuesFull() public {
        assertEq(s_parentPool.areQueuesFull(), false);

        _baseSetup();

        _setQueuesLength(DEFAULT_TARGET_QUEUE_LENGTH, DEFAULT_TARGET_QUEUE_LENGTH);

        for (uint256 i; i < DEFAULT_TARGET_QUEUE_LENGTH; i++) {
            _enterDepositQueue(s_user, _addDecimals(100));
        }

        assertEq(s_parentPool.areQueuesFull(), false);

        for (uint256 i; i < DEFAULT_TARGET_QUEUE_LENGTH; i++) {
            _mintLpToken(s_user, _addDecimals(100));
            _enterWithdrawalQueue(s_user, _addDecimals(100));
        }

        assertEq(s_parentPool.areQueuesFull(), true);
    }

    function test_isReadyToProcessPendingWithdrawals() public {
        assertEq(s_parentPool.isReadyToProcessPendingWithdrawals(), false);

        _baseSetupWithLPMinting();
        address user1 = _getUsers(1)[0];

        _enterWithdrawalQueue(user1, _takeRebalancerFee(_addDecimals(2_000)));
        _fillChildPoolSnapshots(_addDecimals(1000));
        _triggerDepositWithdrawProcess();

        _fillDeficit(_addDecimals(1_800));

        assertEq(s_parentPool.isReadyToProcessPendingWithdrawals(), true);
    }

    function test_setAverageConceroMessageFee_Success() public {
        uint96 averageConceroMessageFee = 1e6;

        vm.prank(s_deployer);
        s_parentPool.setAverageConceroMessageFee(averageConceroMessageFee);

        _baseSetupWithLPMinting();
        address user1 = _getUsers(1)[0];

        _enterWithdrawalQueue(user1, _takeRebalancerFee(_addDecimals(2_000)));
        _fillChildPoolSnapshots(_addDecimals(1000));
        _triggerDepositWithdrawProcess();

        (uint256 conceroFee, ) = s_parentPool.getWithdrawalFee(_addDecimals(2_000));

        _fillDeficit(_addDecimals(1_800));
        _processPendingWithdrawals();

        assertEq(s_parentPool.exposed_getLancaFeeInLiqToken(), conceroFee);
    }

    function test_getActiveBalance() public {
        assertEq(s_parentPool.getActiveBalance(), 0);

        _mintUsdc(address(s_parentPool), _addDecimals(1_000));
        assertEq(s_parentPool.getActiveBalance(), _addDecimals(1_000));

        _enterDepositQueue(s_user, _addDecimals(100));
        assertEq(s_parentPool.getActiveBalance(), _addDecimals(1_000));

        _mintLpToken(s_user, _addDecimals(100));
        assertEq(s_parentPool.getActiveBalance(), _addDecimals(1_000));

        _enterWithdrawalQueue(s_user, _addDecimals(100));
        assertEq(s_parentPool.getActiveBalance(), _addDecimals(1_000));
    }

    function test_getMinDepositQueueLength() public {
        assertEq(s_parentPool.getMinDepositQueueLength(), DEFAULT_TARGET_QUEUE_LENGTH);

        _setQueuesLength(100, 0);
        assertEq(s_parentPool.getMinDepositQueueLength(), 100);
    }

    function test_getMinWithdrawalQueueLength() public {
        assertEq(s_parentPool.getMinWithdrawalQueueLength(), DEFAULT_TARGET_QUEUE_LENGTH);

        _setQueuesLength(0, 100);
        assertEq(s_parentPool.getMinWithdrawalQueueLength(), 100);
    }

    function test_getPendingWithdrawalIds() public {
        assertEq(s_parentPool.getPendingWithdrawalIds().length, 0);
        _setQueuesLength(0, 0);

        _mintLpToken(s_user, _addDecimals(1000));
        _enterWithdrawalQueue(s_user, _addDecimals(500));
        _enterWithdrawalQueue(s_user, _addDecimals(500));
        _fillChildPoolSnapshots();
        _triggerDepositWithdrawProcess();

        assertEq(s_parentPool.getPendingWithdrawalIds().length, 2);
    }

    function test_getLurScoreSensitivity() public {
        assertEq(s_parentPool.getLurScoreSensitivity(), uint64(5 * LIQ_TOKEN_SCALE_FACTOR));

        vm.prank(s_deployer);
        s_parentPool.setLurScoreSensitivity(uint64(4 * LIQ_TOKEN_SCALE_FACTOR));
        assertEq(s_parentPool.getLurScoreSensitivity(), uint64(4 * LIQ_TOKEN_SCALE_FACTOR));
    }

    function test_getScoresWeights() public {
        (uint64 lurScoreWeight, uint64 ndrScoreWeight) = s_parentPool.getScoresWeights();
        assertEq(lurScoreWeight, uint64((7 * LIQ_TOKEN_SCALE_FACTOR) / 10));
        assertEq(ndrScoreWeight, uint64((3 * LIQ_TOKEN_SCALE_FACTOR) / 10));

        vm.prank(s_deployer);
        s_parentPool.setScoresWeights(
            uint64((6 * LIQ_TOKEN_SCALE_FACTOR) / 10),
            uint64((4 * LIQ_TOKEN_SCALE_FACTOR) / 10)
        );

        (lurScoreWeight, ndrScoreWeight) = s_parentPool.getScoresWeights();
        assertEq(lurScoreWeight, uint64((6 * LIQ_TOKEN_SCALE_FACTOR) / 10));
        assertEq(ndrScoreWeight, uint64((4 * LIQ_TOKEN_SCALE_FACTOR) / 10));
    }

    function test_getLiquidityCap() public {
        assertEq(s_parentPool.getLiquidityCap(), 0);

        vm.prank(s_deployer);
        s_parentPool.setLiquidityCap(100);
        assertEq(s_parentPool.getLiquidityCap(), 100);
    }

    function test_getMinDepositAmount() public {
        assertEq(s_parentPool.getMinDepositAmount(), _addDecimals(100));

        vm.prank(s_deployer);
        s_parentPool.setMinDepositAmount(uint64(_addDecimals(50)));
        assertEq(s_parentPool.getMinDepositAmount(), _addDecimals(50));
    }

    function test_getMinWithdrawalAmount() public {
        assertEq(s_parentPool.getMinWithdrawalAmount(), _addDecimals(100));

        vm.prank(s_deployer);
        s_parentPool.setMinWithdrawalAmount(uint64(_addDecimals(50)));

        assertEq(s_parentPool.getMinWithdrawalAmount(), _addDecimals(50));
    }

    /** -- Test Admin Functions Unauthorized Caller -- */

    function test_triggerDepositWithdrawProcess_RevertsUnauthorizedCaller() public {
        vm.expectRevert(
            abi.encodeWithSelector(ICommonErrors.UnauthorizedCaller.selector, s_user, s_lancaKeeper)
        );

        vm.prank(s_user);
        s_parentPool.triggerDepositWithdrawProcess();
    }

    function test_processPendingWithdrawals_RevertsUnauthorizedCaller() public {
        vm.expectRevert(
            abi.encodeWithSelector(ICommonErrors.UnauthorizedCaller.selector, s_user, s_lancaKeeper)
        );

        vm.prank(s_user);
        s_parentPool.processPendingWithdrawals();
    }

    function test_setMinDepositQueueLength_RevertsUnauthorizedCaller() public {
        vm.expectRevert(
            abi.encodeWithSelector(ICommonErrors.UnauthorizedCaller.selector, s_user, s_deployer)
        );

        vm.prank(s_user);
        s_parentPool.setMinDepositQueueLength(100);
    }

    function test_setMinWithdrawalQueueLength_RevertsUnauthorizedCaller() public {
        vm.expectRevert(
            abi.encodeWithSelector(ICommonErrors.UnauthorizedCaller.selector, s_user, s_deployer)
        );

        vm.prank(s_user);
        s_parentPool.setMinWithdrawalQueueLength(100);
    }

    function test_setDstPool_RevertsUnauthorizedCaller() public {
        vm.expectRevert(
            abi.encodeWithSelector(ICommonErrors.UnauthorizedCaller.selector, s_user, s_deployer)
        );

        vm.prank(s_user);
        s_parentPool.setDstPool(1, address(0).toBytes32());
    }

    function test_setLurScoreSensitivity_RevertsUnauthorizedCaller() public {
        vm.expectRevert(
            abi.encodeWithSelector(ICommonErrors.UnauthorizedCaller.selector, s_user, s_deployer)
        );

        vm.prank(s_user);
        s_parentPool.setLurScoreSensitivity(100);
    }

    function test_setScoresWeights_RevertsUnauthorizedCaller() public {
        vm.expectRevert(
            abi.encodeWithSelector(ICommonErrors.UnauthorizedCaller.selector, s_user, s_deployer)
        );

        vm.prank(s_user);
        s_parentPool.setScoresWeights(100, 100);
    }

    function test_setLiquidityCap_RevertsUnauthorizedCaller() public {
        vm.expectRevert(
            abi.encodeWithSelector(ICommonErrors.UnauthorizedCaller.selector, s_user, s_deployer)
        );

        vm.prank(s_user);
        s_parentPool.setLiquidityCap(100);
    }

    function test_setMinDepositAmount_RevertsUnauthorizedCaller() public {
        vm.expectRevert(
            abi.encodeWithSelector(ICommonErrors.UnauthorizedCaller.selector, s_user, s_deployer)
        );

        vm.prank(s_user);
        s_parentPool.setMinDepositAmount(100);
    }

    function test_setAverageConceroMessageFee_RevertsUnauthorizedCaller() public {
        vm.expectRevert(
            abi.encodeWithSelector(ICommonErrors.UnauthorizedCaller.selector, s_user, s_deployer)
        );

        vm.prank(s_user);
        s_parentPool.setAverageConceroMessageFee(100);
    }

    /** -- Concero receive functions -- */

    function test_handleConceroReceiveUpdateTargetBalance_RevertsFunctionNotImplemented() public {
        IConceroRouter.MessageRequest memory messageRequest = _buildMessageRequest(
            BridgeCodec.encodeUpdateTargetBalanceData(0, USDC_TOKEN_DECIMALS),
            PARENT_POOL_CHAIN_SELECTOR,
            address(s_parentPool)
        );

        vm.expectRevert(ICommonErrors.FunctionNotImplemented.selector);

        vm.prank(s_conceroRouter);
        s_parentPool.conceroReceive(
            messageRequest.toMessageReceiptBytes(CHILD_POOL_CHAIN_SELECTOR, address(0), NONCE),
            s_validationChecks,
            s_validatorLibs,
            s_relayerLib
        );
    }
}
