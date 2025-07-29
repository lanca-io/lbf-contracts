import { ChildProcessWithoutNullStreams, spawn } from "child_process";

import "./configureEnv";

import { initializeManagers } from "@lanca/rebalancer/src/utils/initializeManagers";

import { deployLPToken } from "../../deploy/00_deploy_lptoken";
import { deployIOUToken } from "../../deploy/01_deploy_ioutoken";
import { deployParentPool } from "../../deploy/02_deploy_parentpool";
import { deployChildPool } from "../../deploy/03_deploy_childpool";
import { deployMockERC20 } from "../../deploy/05_deploy_mock_erc20";
import { compileContractsAsync } from "../../utils/compileContracts";

type Deployment = {
	LPToken: string;
	IOUToken: string;
	ParentPool: string;
	ChildPool: string;
	USDC: string;
};

export class RebalancerIntegrationTestSetup {
	private node: ChildProcessWithoutNullStreams | null = null;
	private disposed = false;

	async setup(): Promise<void> {
		this.registerSignalHandlers();

		// Start blockchain and compile contracts in parallel
		await Promise.all([this.startBlockchain(), compileContractsAsync({ quiet: true })]);

		const deployments = {
			chain1: await this.deployContracts(),
			chain2: await this.deployContracts(),
		};

		const config = await this.configureRebalancer(deployments);
		await initializeManagers(config);
	}

	private async startBlockchain(): Promise<void> {
		this.node = spawn("npm", ["run", "chain"], { stdio: "inherit" });
		await new Promise(r => setTimeout(r, 3_000)); // wait for node to be ready
	}

	private async deployContracts(): Promise<Deployment> {
		// Ensure we're using the localhost network
		process.env.HARDHAT_NETWORK = "localhost";

		const hre = require("hardhat");

		try {
			// Clear deployments directory to ensure fresh deployments
			const deployments = hre.deployments;
			await deployments.delete("LPToken");
			await deployments.delete("IOUToken");
			await deployments.delete("ParentPool");
			await deployments.delete("ChildPool");
			await deployments.delete("MockERC20");

			return {
				LPToken: (await deployLPToken(hre)).address,
				IOUToken: (await deployIOUToken(hre)).address,
				ParentPool: (await deployParentPool(hre)).address,
				ChildPool: (await deployChildPool(hre)).address,
				USDC: (await deployMockERC20(hre)).address,
			};
		} finally {
			delete process.env.HARDHAT_NETWORK;
		}
	}

	private async configureRebalancer(deployments: {
		chain1: Deployment;
		chain2: Deployment;
	}): Promise<any> {
		process.env.NETWORK_MODE = "localhost";
		process.env.OPERATOR_ADDRESS = "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266";
		process.env.OPERATOR_PRIVATE_KEY =
			"ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80";

		// Structure config to match deploymentManager expectations
		// Use network names as keys to match deploymentManager parsing logic
		return {
			localhostDeployments: {
				pools: new Map([
					["localhost1", deployments.chain1.ChildPool],
					["localhost2", deployments.chain2.ChildPool],
				]),
				parentPool: {
					network: "localhost1",
					address: deployments.chain1.ParentPool,
				},
				usdcTokens: new Map([
					["localhost1", deployments.chain1.USDC],
					["localhost2", deployments.chain2.USDC],
				]),
				iouTokens: new Map([
					["localhost1", deployments.chain1.IOUToken],
					["localhost2", deployments.chain2.IOUToken],
				]),
			},
			// Provide localhost networks for LancaNetworkManager
			localhostNetworks: [
				{
					id: 31337,
					name: "localhost1",
					displayName: "Localhost Chain 1",
					rpcUrls: ["http://127.0.0.1:8545"],
					chainSelector: "1",
					isTestnet: true,
				},
				{
					id: 31338,
					name: "localhost2",
					displayName: "Localhost Chain 2",
					rpcUrls: ["http://127.0.0.1:8545"],
					chainSelector: "2",
					isTestnet: true,
				},
			],
		};
	}
	/** Ensures the Hardhat node is always terminated. */
	async teardown(): Promise<void> {
		if (this.disposed) return;
		this.disposed = true;
		this.node?.kill("SIGTERM");
	}

	/** Register process-level listeners for graceful shutdown. */
	private registerSignalHandlers(): void {
		const shutdown = async () => {
			await this.teardown();
			process.exit(0);
		};
		process.once("SIGINT", shutdown);
		process.once("SIGTERM", shutdown);
		process.once("exit", () => this.teardown());
	}
}

export const testSetup = new RebalancerIntegrationTestSetup();
testSetup.setup();
