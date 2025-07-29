import { ChildProcessWithoutNullStreams, spawn } from "child_process";

import "./configureEnv";

import { DeployOptions } from "hardhat-deploy/types";

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

		await Promise.all([this.startBlockchain(), compileContractsAsync({ quiet: true })]);

		const deployments = await this.deployContracts();

		const config = await this.configureRebalancer(deployments);
		console.log(config);

		await initializeManagers(config);
	}

	private async startBlockchain(): Promise<void> {
		this.node = spawn("npm", ["run", "chain"], { stdio: "inherit" });

		while (true) {
			try {
				await fetch("http://127.0.0.1:8545", {
					method: "POST",
					body: '{"jsonrpc":"2.0","method":"eth_blockNumber","id":1}',
				});
				break;
			} catch {}
			await new Promise(r => setTimeout(r, 100));
		}
	}

	private async deployContracts(): Promise<Deployment> {
		const hre = require("hardhat");
		const deployOptions: Partial<DeployOptions> = {
			log: false,
		};

		try {
			// Clear deployments directory to ensure fresh deployments
			const deployments = hre.deployments;
			await deployments.delete("LPToken");
			await deployments.delete("IOUToken");
			await deployments.delete("MockERC20");
			await deployments.delete("ParentPool");
			await deployments.delete("ChildPool");

			return {
				// Pool dependencies
				LPToken: (await deployLPToken(hre, deployOptions)).address,
				IOUToken: (await deployIOUToken(hre, deployOptions)).address,
				USDC: (await deployMockERC20(hre, deployOptions)).address,
				// Pools
				ParentPool: (await deployParentPool(hre, deployOptions)).address,
				ChildPool: (await deployChildPool(hre, deployOptions)).address,
			};
		} finally {
			delete process.env.HARDHAT_NETWORK;
		}
	}

	private async configureRebalancer(deployments: Deployment): Promise<any> {
		return {
			// for DeploymentManager
			localhostDeployments: {
				pools: {
					localhost2: deployments.ChildPool,
				},
				parentPool: {
					network: "localhost1",
					address: deployments.ParentPool,
				},
				usdcTokens: {
					localhost1: deployments.USDC,
					localhost2: deployments.USDC,
				},
				iouTokens: {
					localhost1: deployments.IOUToken,
					localhost2: deployments.IOUToken,
				},
			},
			// for LancaNetworkManager
			localhostNetworks: [
				{
					id: 1,
					name: "localhost1",
					displayName: "Localhost Chain 1",
					rpcUrls: ["http://127.0.0.1:8545"],
					chainSelector: "1",
					isTestnet: true,
				},
				{
					id: 2,
					name: "localhost2",
					displayName: "Localhost Chain 2",
					rpcUrls: ["http://127.0.0.1:8545"],
					chainSelector: "2",
					isTestnet: true,
				},
			],
		};
	}

	async teardown(): Promise<void> {
		if (this.disposed) return;
		this.disposed = true;
		this.node?.kill("SIGTERM");
	}

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
