import { expect } from "chai";

import { parseUnits } from "viem";

import { TEST_CONSTANTS } from "./constants";
import { StateManager } from "./utils/StateManager";

const USDC_DECIMALS = TEST_CONSTANTS.USDC_DECIMALS;
const { LPToken, IOUToken, ParentPool, ChildPool, USDC } = global.deployments;
const operator = process.env.OPERATOR_ADDRESS;
const stateManager = new StateManager({
	parentPool: ParentPool,
	childPool: ChildPool,
	usdc: USDC,
	iouToken: IOUToken,
	lpToken: LPToken,
});

describe("Automatic Rebalancing", function () {
	it("rebalancer fills deficit automatically", async function () {
		await stateManager.mintTokens(
			IOUToken,
			operator,
			parseUnits(
				TEST_CONSTANTS.DEFAULT_IOU_MINT_AMOUNT,
				TEST_CONSTANTS.DEFAULT_TOKEN_DECIMALS,
			),
		);
		await stateManager.mintTokens(
			USDC,
			operator,
			parseUnits(TEST_CONSTANTS.DEFAULT_USDC_MINT_AMOUNT, USDC_DECIMALS),
		);
		await stateManager.createDeficitState(ChildPool, parseUnits("100", USDC_DECIMALS));

		const state = await stateManager.getPoolState(ChildPool);
		console.log("state: ", state);

		const event = await stateManager.waitForRebalancerEvent(
			ChildPool,
			"DeficitFilled",
			TEST_CONSTANTS.EVENT_TIMEOUT,
		);

		expect(state.currentDeficit).to.equal(0n);

		const log = event.logs[0];
		expect(log.eventName).to.equal("DeficitFilled");
	});

	// it("rebalancer takes surplus automatically", async function () {
	// 	const pool = addresses.parentPool;
	// 	const surplus = parseUnits("15000", USDC_DECIMALS);

	// 	await stateManager.createSurplusState(pool, surplus);

	// 	const event = await stateManager.waitForRebalancerEvent(pool, "SurplusTaken", 45000);

	// 	const state = await stateManager.getPoolState(pool);
	// 	expect(state.currentSurplus).to.equal(0n);

	// 	const log = event.logs[0];
	// 	expect(log.eventName).to.equal("SurplusTaken");
	// });

	// it("rebalancer handles partial deficit over time", async function () {
	// 	const pool = addresses.parentPool;
	// 	const largeDeficit = parseUnits("50000", USDC_DECIMALS);

	// 	await stateManager.createDeficitState(pool, largeDeficit);

	// 	await stateManager.waitForBalancedState(pool, 120000);

	// 	const state = await stateManager.getPoolState(pool);
	// 	expect(state.currentDeficit).to.equal(0n);
	// 	expect(state.currentSurplus).to.equal(0n);
	// });
});

// describe("Edge Cases", function () {
// 	it("handles zero balances", async function () {
// 		const pool = addresses.childPool;
// 		await stateManager.setTargetBalance(pool, 0n);

// 		const state = await stateManager.getPoolState(pool);
// 		expect(state.currentDeficit).to.equal(0n);
// 		expect(state.currentSurplus).to.equal(0n);
// 	});

// 	it("handles large imbalances", async function () {
// 		const pool = addresses.parentPool;
// 		const largeDeficit = parseUnits("1000000", USDC_DECIMALS);

// 		await stateManager.createDeficitState(pool, largeDeficit);

// 		const state = await stateManager.getPoolState(pool);
// 		expect(state.currentDeficit).to.equal(largeDeficit);
// 	});
// });
