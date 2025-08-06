import ChildPoolArtifact from "../../../artifacts/contracts/ChildPool/ChildPool.sol/ChildPool.json";
import ParentPoolArtifact from "../../../artifacts/contracts/ParentPool/ParentPool.sol/ParentPool.json";
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
			ChildPoolArtifact,
			ParentPoolArtifact,
		);
	}

	async setupContracts(): Promise<void> {
		await this.setEthBalance(deployer, TEST_CONSTANTS.DEFAULT_ETH_BALANCE);
		await this.setEthBalance(operator!, TEST_CONSTANTS.DEFAULT_ETH_BALANCE);
	}

	async waitForRebalancerEvent(
		poolAddress: `0x${string}`,
		eventName: "DeficitFilled" | "SurplusTaken",
		timeoutMs: number,
	): Promise<any> {
		const poolAbi = ParentPoolArtifact.abi;
		return this.waitForEvent(
			poolAddress,
			poolAbi,
			eventName,
			timeoutMs,
			TEST_CONSTANTS.EVENT_POLLING_INTERVAL_MS,
		);
	}

	async resetState(): Promise<void> {
		// Reset pool balances to 0
		await this.setTokenBalance(
			this.deployments.USDC as `0x${string}`,
			this.deployments.ParentPool as `0x${string}`,
			0n,
		);
		await this.setTokenBalance(
			this.deployments.USDC as `0x${string}`,
			this.deployments.ChildPool as `0x${string}`,
			0n,
		);

		// Reset operator USDC and IOU balances to 0
		await this.setTokenBalance(this.deployments.USDC as `0x${string}`, operator!, 0n);
		await this.setTokenBalance(this.deployments.IOUToken! as `0x${string}`, operator!, 0n);

		// Reset operator allowances to 0 for USDC
		await this.setAllowance(
			this.deployments.USDC as `0x${string}`,
			operator!,
			this.deployments.ParentPool as `0x${string}`,
			0n,
		);
		await this.setAllowance(
			this.deployments.USDC as `0x${string}`,
			operator!,
			this.deployments.ChildPool as `0x${string}`,
			0n,
		);

		// Reset operator allowances to 0 for IOU tokens
		await this.setAllowance(
			this.deployments.IOUToken! as `0x${string}`,
			operator!,
			this.deployments.ParentPool as `0x${string}`,
			0n,
		);
		await this.setAllowance(
			this.deployments.IOUToken! as `0x${string}`,
			operator!,
			this.deployments.ChildPool as `0x${string}`,
			0n,
		);

		// Reset pool target balances to 0
		await this.setTargetBalance(this.deployments.ParentPool as `0x${string}`, 0n);
		await this.setTargetBalance(this.deployments.ChildPool as `0x${string}`, 0n);
	}
}
