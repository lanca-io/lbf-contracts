import { parseAbi, parseAbiItem } from "viem";

import { Deployment, StateManagerBase, TestConstants } from "./StateManagerBase";

const deployer = process.env.LOCALHOST_DEPLOYER_ADDRESS as `0x${string}`;

export interface PoolState {
	activeBalance: bigint;
	targetBalance: bigint;
	currentDeficit: bigint;
	currentSurplus: bigint;
}

export class PoolStateManager extends StateManagerBase {
	private childPoolWrapperArtifact?: any;
	private parentPoolWrapperArtifact?: any;

	constructor(
		deployments: Deployment,
		testConstants: TestConstants,
		childPoolWrapperArtifact?: any,
		parentPoolWrapperArtifact?: any,
	) {
		super(deployments, testConstants);
		this.childPoolWrapperArtifact = childPoolWrapperArtifact;
		this.parentPoolWrapperArtifact = parentPoolWrapperArtifact;
	}

	async getPoolState(poolAddress: `0x${string}`): Promise<PoolState> {
		const poolAbi = this.getPoolWrapperAbi(poolAddress);

		const [activeBalance, targetBalance, currentDeficit, currentSurplus] = await Promise.all([
			this.testClient.readContract({
				address: poolAddress,
				abi: poolAbi,
				functionName: "getActiveBalance",
			}) as Promise<bigint>,
			this.testClient.readContract({
				address: poolAddress,
				abi: poolAbi,
				functionName: "getTargetBalance",
			}) as Promise<bigint>,
			this.testClient.readContract({
				address: poolAddress,
				abi: poolAbi,
				functionName: "getDeficit",
			}) as Promise<bigint>,
			this.testClient.readContract({
				address: poolAddress,
				abi: poolAbi,
				functionName: "getSurplus",
			}) as Promise<bigint>,
		]);

		return {
			activeBalance,
			targetBalance,
			currentDeficit,
			currentSurplus,
		};
	}

	async setTargetBalance(poolAddress: `0x${string}`, newTargetBalance: bigint): Promise<void> {
		await this.testClient.writeContract({
			address: poolAddress,
			abi: [parseAbiItem("function setTargetBalance(uint256 newTargetBalance)")],
			functionName: "setTargetBalance",
			args: [newTargetBalance],
			account: deployer,
		});
	}

	protected getPoolWrapperAbi(poolAddress: `0x${string}`) {
		return poolAddress === this.deployments.ParentPool
			? this.parentPoolWrapperArtifact?.abi
			: this.childPoolWrapperArtifact?.abi;
	}
}
