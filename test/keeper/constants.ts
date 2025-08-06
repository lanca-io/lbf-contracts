import { SHARED_TEST_CONSTANTS } from "../shared/constants";

export const TEST_CONSTANTS = {
	...SHARED_TEST_CONSTANTS,

	// Keeper-specific intervals
	KEEPER_POLLING_INTERVAL: 2000,
} as const;

export const EVENT_NAMES = {
	SNAPSHOT_SENT: "SnapshotSent",
	DEPOSIT_WITHDRAW_TRIGGERED: "DepositWithdrawTriggered",
	PENDING_WITHDRAWALS_PROCESSED: "PendingWithdrawalsProcessed",
} as const;
