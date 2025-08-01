import { IOU_TOKEN_DECIMALS, USDC_DECIMALS } from "@lanca/rebalancer/src/constants";
import { expect } from "chai";
import { parseUnits } from "viem";

import { TEST_CONSTANTS } from "./constants";
import { StateManager } from "./utils/StateManager";

const { LPToken, IOUToken, ParentPool, ChildPool, USDC } = global.deployments;
const operator = process.env.OPERATOR_ADDRESS;
const stateManager = new StateManager({
	ParentPool: ParentPool,
	ChildPool: ChildPool,
	USDC: USDC,
	IOUToken: IOUToken,
	LPToken: LPToken,
});

describe("Automatic Rebalancing", function () {
	beforeEach(async function () {
		await stateManager.resetState();
	});

	it("rebalancer fills deficit automatically", async function () {
		await stateManager.mintTokens(USDC, operator, parseUnits("100", USDC_DECIMALS));
		await stateManager.createDeficitState(ChildPool, parseUnits("100", USDC_DECIMALS));

		const event = await stateManager.waitForRebalancerEvent(
			ChildPool,
			"DeficitFilled",
			TEST_CONSTANTS.EVENT_TIMEOUT,
		);

		const state = await stateManager.getPoolState(ChildPool);
		expect(state.currentDeficit).to.equal(0n);

		const log = event.logs[0];
		expect(log.eventName).to.equal("DeficitFilled");
	});

	it("rebalancer takes surplus automatically", async function () {
		await stateManager.mintTokens(IOUToken, operator, parseUnits("100", IOU_TOKEN_DECIMALS));
		await stateManager.mintTokens(USDC, ChildPool, parseUnits("100", USDC_DECIMALS));

		const event = await stateManager.waitForRebalancerEvent(
			ChildPool,
			"SurplusTaken",
			TEST_CONSTANTS.EVENT_TIMEOUT,
		);

		const state = await stateManager.getPoolState(ChildPool);
		expect(state.currentSurplus).to.equal(0n);

		const log = event.logs[0];
		expect(log.eventName).to.equal("SurplusTaken");
	});
});
