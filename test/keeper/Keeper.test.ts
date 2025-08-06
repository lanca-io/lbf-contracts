import { beforeEach, describe, it } from "mocha";

import { StateManager } from "./utils/StateManager";

const { ParentPool, ChildPool } = global.deployments;

const operator = process.env.OPERATOR_ADDRESS;

const stateManager = new StateManager({
	ParentPool: ParentPool,
	ChildPool: ChildPool,
});

describe("Keeper Integration Tests", () => {
	beforeEach(async () => {
		await stateManager.resetState();
	});

	describe("Keeper triggers snapshot when queues are full", () => {
		it("should trigger snapshot from child pool when parent pool queues are full", async () => {
			await stateManager.setQueuesFull(ParentPool, true);
			await stateManager.waitForKeeperEvent(ChildPool, "SnapshotSent", 10000);
		});

		it("should trigger deposit withdraw process when ready", async () => {
			await stateManager.setReadyToTriggerDepositWithdrawProcess(ParentPool, true);
			await stateManager.waitForKeeperEvent(ParentPool, "DepositWithdrawTriggered", 10000);
		});

		it("should process pending withdrawals when ready", async () => {
			await stateManager.setReadyToProcessPendingWithdrawals(ParentPool, true);
			await stateManager.waitForKeeperEvent(ParentPool, "PendingWithdrawalsProcessed", 10000);
		});
	});
});
