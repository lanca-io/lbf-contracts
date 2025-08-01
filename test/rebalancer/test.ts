import "./configureEnv";

import { ChildProcessWithoutNullStreams, spawn } from "child_process";
import path from "path";

import { initializeManagers } from "@lanca/rebalancer/src/utils/initializeManagers";
import { DeployOptions } from "hardhat-deploy/types";
import Mocha from "mocha";

import { deployLPToken } from "../../deploy/00_deploy_lptoken";
import { deployIOUToken } from "../../deploy/01_deploy_ioutoken";
import { deployParentPool } from "../../deploy/02_deploy_parentpool";
import { deployChildPool } from "../../deploy/03_deploy_childpool";
import { deployMockERC20 } from "../../deploy/05_deploy_mock_erc20";
import { setChildPoolVariables } from "../../tasks/deployChildPool";
import { setParentPoolVariables } from "../../tasks/deployParentPool";
import { compileContractsAsync } from "../../utils/compileContracts";
import { TEST_CONSTANTS } from "./constants";
import { StateManager } from "./utils/StateManager";
import { localhostViemChain } from "./utils/localhostViemChain";

export type Deployment = {
	LPToken: string;
	IOUToken: string;
	ParentPool: string;
	ChildPool: string;
	USDC: string;
};

const hre = require("hardhat");

export class RebalancerIntegrationTest {
	private node: ChildProcessWithoutNullStreams | null = null;
	private disposed = false;

	async run(): Promise<void> {
		this.registerSignalHandlers();

		// Parse CLI flags
		const args = process.argv.slice(2);
		const skipRebalancer = args.includes("--skip-rebalancer");

		await Promise.all([this.runChain(), compileContractsAsync({ quiet: true })]);

		const deployments = await this.deployContracts();
		await setChildPoolVariables(hre);
		await setParentPoolVariables(hre);

		const stateManager = new StateManager(deployments);
		await stateManager.setupContracts();

		const config = await this.configureRebalancer(deployments);
		// Conditionally initialize managers
		if (!skipRebalancer) {
			await initializeManagers(config);
		} else {
			console.log("Skipping initializeManagers due to --skip-rebalancer flag");
		}

		// Running Mocha
		(global as any).deployments = deployments;
		const mocha = new Mocha({
			timeout: TEST_CONSTANTS.DEFAULT_TIMEOUT,
			ui: "bdd",
			reporter: "spec",
		});
		mocha.addFile(path.resolve(__dirname, "Rebalancer.test.ts"));
		mocha.run(failures => (process.exitCode = failures ? 1 : 0));
	}

	private async runChain(): Promise<void> {
		this.node = spawn("npm", ["run", "chain"], {
			stdio: "inherit",
		}) as ChildProcessWithoutNullStreams;

		while (true) {
			try {
				await fetch(TEST_CONSTANTS.LOCALHOST_URL, {
					method: "POST",
					body: '{"jsonrpc":"2.0","method":"eth_blockNumber","id":1}',
				});
				break;
			} catch {}
			await new Promise(r => setTimeout(r, 100));
		}
	}

	public async deployContracts(): Promise<Deployment> {
		const deployOptions: Partial<DeployOptions> = {
			log: false,
		};

		try {
			return {
				LPToken: (await deployLPToken(hre, deployOptions)).address,
				IOUToken: (await deployIOUToken(hre, deployOptions)).address,
				USDC: (await deployMockERC20(hre, deployOptions)).address,
				ParentPool: (
					await deployParentPool(hre, { ...deployOptions, contract: "ParentPoolWrapper" })
				).address,
				ChildPool: (
					await deployChildPool(hre, { ...deployOptions, contract: "ChildPoolWrapper" })
				).address,
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
					id: TEST_CONSTANTS.LOCALHOST_CHAIN_ID,
					name: "localhost1",
					displayName: "Localhost Chain 1",
					rpcUrls: [TEST_CONSTANTS.LOCALHOST_URL],
					chainSelector: "2",
					isTestnet: true,
					viemChain: {
						...localhostViemChain,
						id: TEST_CONSTANTS.LOCALHOST_CHAIN_ID,
						name: "Localhost 1",
						network: "localhost1",
						nativeCurrency: {
							NAME: "Ether",
							SYMBOL: "ETH",
							DECIMALS: 18,
						},
						rpcUrls: {
							default: {
								http: [TEST_CONSTANTS.LOCALHOST_URL],
							},
							public: {
								http: [TEST_CONSTANTS.LOCALHOST_URL],
							},
						},
					},
				},
				{
					id: 2,
					name: "localhost2",
					displayName: "Localhost Chain 2",
					rpcUrls: [TEST_CONSTANTS.LOCALHOST_URL],
					chainSelector: "2",
					isTestnet: true,
					viemChain: {
						...localhostViemChain,
						id: TEST_CONSTANTS.LOCALHOST_CHAIN_ID,
						name: "Localhost 2",
						network: "localhost2",
						nativeCurrency: {
							NAME: "Ether",
							SYMBOL: "ETH",
							DECIMALS: 18,
						},
						rpcUrls: {
							default: {
								http: [TEST_CONSTANTS.LOCALHOST_URL],
							},
							public: {
								http: [TEST_CONSTANTS.LOCALHOST_URL],
							},
						},
					},
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

const test = new RebalancerIntegrationTest();
test.run();
