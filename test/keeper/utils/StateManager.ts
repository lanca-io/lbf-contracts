import ChildPoolWrapperArtifact from "../../../artifacts/contracts/test-helpers/KeeperChildPoolWrapper.sol/KeeperChildPoolWrapper.json";
import ParentPoolWrapperArtifact from "../../../artifacts/contracts/test-helpers/KeeperParentPoolWrapper.sol/KeeperParentPoolWrapper.json";
import { PoolStateManager } from "../../shared/PoolStateManager";
import { TEST_CONSTANTS } from "../constants";
import { Deployment } from "../test";

const deployer = process.env.LOCALHOST_DEPLOYER_ADDRESS as `0x${string}`;
const operator = process.env.OPERATOR_ADDRESS as `0x${string}`;

export class StateManager extends PoolStateManager {
	constructor(deployments: Deployment) {
		super(
			deployments,
			{
				LOCALHOST_URL: TEST_CONSTANTS.LOCALHOST_URL,
				DEFAULT_ETH_BALANCE: TEST_CONSTANTS.DEFAULT_ETH_BALANCE,
				EVENT_POLLING_INTERVAL_MS: TEST_CONSTANTS.EVENT_POLLING_INTERVAL_MS,
			},
			ChildPoolWrapperArtifact,
			ParentPoolWrapperArtifact,
		);
	}

	async setupContracts(): Promise<void> {
		await this.setEthBalance(deployer, TEST_CONSTANTS.DEFAULT_ETH_BALANCE);
		await this.setEthBalance(operator!, TEST_CONSTANTS.DEFAULT_ETH_BALANCE);
	}

	// Setter methods for manipulating keeper-specific contract state
	async setQueuesFull(parentPoolAddress: `0x${string}`, full: boolean): Promise<void> {
		await this.testClient.writeContract({
			address: parentPoolAddress,
			abi: ParentPoolWrapperArtifact.abi,
			functionName: "setQueuesFull",
			args: [full],
			account: deployer,
		});
	}

	async setReadyToTriggerDepositWithdrawProcess(
		parentPoolAddress: `0x${string}`,
		ready: boolean,
	): Promise<void> {
		await this.testClient.writeContract({
			address: parentPoolAddress,
			abi: ParentPoolWrapperArtifact.abi,
			functionName: "setReadyToTriggerDepositWithdrawProcess",
			args: [ready],
			account: deployer,
		});
	}

	async setReadyToProcessPendingWithdrawals(
		parentPoolAddress: `0x${string}`,
		ready: boolean,
	): Promise<void> {
		await this.testClient.writeContract({
			address: parentPoolAddress,
			abi: ParentPoolWrapperArtifact.abi,
			functionName: "setReadyToProcessPendingWithdrawals",
			args: [ready],
			account: deployer,
		});
	}

	async resetState(): Promise<void> {}

	// Keeper-specific action methods
	async triggerDepositWithdrawProcess(parentPoolAddress: `0x${string}`): Promise<void> {
		await this.testClient.writeContract({
			address: parentPoolAddress,
			abi: ParentPoolWrapperArtifact.abi,
			functionName: "triggerDepositWithdrawProcess",
			account: deployer,
		});
	}

	async processPendingWithdrawals(parentPoolAddress: `0x${string}`): Promise<void> {
		await this.testClient.writeContract({
			address: parentPoolAddress,
			abi: ParentPoolWrapperArtifact.abi,
			functionName: "processPendingWithdrawals",
			account: deployer,
		});
	}

	async waitForKeeperEvent(
		poolAddress: `0x${string}`,
		eventName: "SnapshotSent" | "DepositWithdrawTriggered" | "PendingWithdrawalsProcessed",
		timeoutMs: number,
	): Promise<any> {
		const poolAbi = this.getPoolWrapperAbi(poolAddress);
		return this.waitForEvent(
			poolAddress,
			poolAbi,
			eventName,
			timeoutMs,
			TEST_CONSTANTS.EVENT_POLLING_INTERVAL_MS,
		);
	}
}

export default StateManager;
