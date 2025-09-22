// SPDX-License-Identifier: UNLICENSED
/* solhint-disable func-name-mixedcase */
pragma solidity 0.8.28;

import {ICommonErrors} from "contracts/common/interfaces/ICommonErrors.sol";
import {ILancaKeeper} from "contracts/ParentPool/interfaces/ILancaKeeper.sol";
import {
    ParentPool,
    IParentPool,
    ParentPoolBase,
    LPToken,
    DeployLPToken,
    console
} from "./ParentPoolBase.sol";

contract ParentPoolTest is ParentPoolBase {
    function setUp() public override {
        super.setUp();
        vm.warp(NOW_TIMESTAMP);
    }

    function test_constructor_RevertsInvalidLiqTokenDecimals() public {
        DeployLPToken deployLPToken = new DeployLPToken();
        LPToken lpToken = LPToken(deployLPToken.deployLPToken(address(this), address(this)));

        uint8 invalidLiqTokenDecimals = 5;

        vm.expectRevert(ParentPool.InvalidLiqTokenDecimals.selector);
        new ParentPool(
            address(usdc),
            invalidLiqTokenDecimals,
            address(lpToken),
            conceroRouter,
            PARENT_POOL_CHAIN_SELECTOR,
            address(iouToken),
            MIN_TARGET_BALANCE
        );
    }

    /** -- Enter Deposit Queue -- */

    function test_enterDepositQueue_RevertsMinDepositAmountNotSet() public {
        vm.prank(deployer);
        s_parentPool.setMinDepositAmount(0);

        vm.expectRevert(ICommonErrors.MinDepositAmountNotSet.selector);
        s_parentPool.enterDepositQueue(100);
    }

    function test_enterDepositQueue_RevertsDepositAmountIsTooLow() public {
        vm.prank(deployer);
        s_parentPool.setMinDepositAmount(100);

        vm.expectRevert(
            abi.encodeWithSelector(ICommonErrors.DepositAmountIsTooLow.selector, 99, 100)
        );
        s_parentPool.enterDepositQueue(99);
    }

    function test_enterDepositQueue_RevertsDepositQueueIsFull() public {
        for (uint256 i; i < 250; i++) {
            _enterDepositQueue(user, _addDecimals(100));
        }

        vm.expectRevert(IParentPool.DepositQueueIsFull.selector);

        vm.prank(user);
        s_parentPool.enterDepositQueue(_addDecimals(100));
    }

    function test_enterDepositQueue_LiquidityCapReached() public {
        _baseSetup();

        uint256 newLiquidityCap = _addDecimals(100);
        _enterDepositQueue(user, newLiquidityCap);

        _triggerDepositWithdrawProcess();

        vm.prank(deployer);
        s_parentPool.setLiquidityCap(newLiquidityCap);

        vm.expectRevert(
            abi.encodeWithSelector(IParentPool.LiquidityCapReached.selector, newLiquidityCap)
        );
        vm.prank(user);
        s_parentPool.enterDepositQueue(newLiquidityCap + 1);
    }

    function test_enterDepositQueue_EmitsDepositQueued() public {
        _baseSetup();

        bytes32 depositId = keccak256(abi.encodePacked(user, block.number, uint256(1)));

        vm.expectEmit(true, true, true, true);
        emit IParentPool.DepositQueued(depositId, user, _addDecimals(100));

        vm.prank(user);
        s_parentPool.enterDepositQueue(_addDecimals(100));
    }

    /** -- Enter Withdrawal Queue -- */

    function test_enterWithdrawalQueue_RevertsAmountIsZero() public {
        vm.expectRevert(ICommonErrors.AmountIsZero.selector);

        vm.prank(user);
        s_parentPool.enterWithdrawalQueue(0);
    }

    function test_enterWithdrawalQueue_RevertsWithdrawalQueueIsFull() public {
        _setQueuesLength(0, 0);
        _enterDepositQueue(user, _addDecimals(1000));

        _fillChildPoolSnapshots();
        _triggerDepositWithdrawProcess();

        for (uint256 i; i < 250; i++) {
            _enterWithdrawalQueue(user, _addDecimals(1));
        }

        vm.expectRevert(IParentPool.WithdrawalQueueIsFull.selector);

        vm.prank(user);
        s_parentPool.enterWithdrawalQueue(1);
    }

    function test_enterWithdrawalQueue_EmitsWithdrawalQueued() public {
        _baseSetup();
        _mintLpToken(user, _addDecimals(1));

        vm.prank(user);
        lpToken.approve(address(s_parentPool), _addDecimals(1));

        bytes32 withdrawalId = keccak256(abi.encodePacked(user, block.number, uint256(1)));

        vm.expectEmit(true, true, true, true);
        emit IParentPool.WithdrawalQueued(withdrawalId, user, _addDecimals(1));

        vm.prank(user);
        s_parentPool.enterWithdrawalQueue(_addDecimals(1));
    }

    /** -- Trigger Deposit Withdraw Process -- */

    function test_triggerDepositWithdrawProcess_RevertsQueuesAreNotFull() public {
        vm.expectRevert(IParentPool.QueuesAreNotFull.selector);

        vm.prank(s_lancaKeeper);
        s_parentPool.triggerDepositWithdrawProcess();
    }

    function test_triggerDepositWithdrawProcess_RevertsChildPoolSnapshotsAreNotReady() public {
        _setQueuesLength(0, 0);
        _enterDepositQueue(user, _addDecimals(100));

        vm.expectRevert(ParentPool.ChildPoolSnapshotsAreNotReady.selector);

        vm.prank(s_lancaKeeper);
        s_parentPool.triggerDepositWithdrawProcess();
    }

    function test_triggerDepositWithdrawProcess_RevertsInvalidDstChainSelector() public {
        _setQueuesLength(0, 0);
        _enterDepositQueue(user, _addDecimals(100));

        uint24 invalidChainSelector = 1;
        s_parentPool.exposed_setDstPool(invalidChainSelector, address(0));

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
}
