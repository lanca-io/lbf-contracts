import "./configureEnv";

import { ChildProcessWithoutNullStreams, spawn } from "child_process";
import path from "path";

import { DeployOptions } from "hardhat-deploy/types";
import Mocha from "mocha";

import { deployParentPool } from "../../deploy/02_deploy_parentpool";
import { deployChildPool } from "../../deploy/03_deploy_childpool";
import { compileContractsAsync } from "../../utils/compileContracts";
import { localhostViemChain } from "../shared/localhostViemChain";
import { TEST_CONSTANTS } from "./constants";
import { StateManager } from "./utils/StateManager";
import { initializeManagers } from "/Users/oleg/Documents/Code/lanca/keeper/src/utils/initializeManagers";

export type Deployment = {
	LPToken: string;
	IOUToken: string;
	ParentPool: string;
	ChildPool: string;
	USDC: string;
};

const hre = require("hardhat");

export class KeeperIntegrationTest {
	private node: ChildProcessWithoutNullStreams | null = null;
	private disposed = false;

	async run(): Promise<void> {
		this.registerSignalHandlers();

		// Parse CLI flags
		const args = process.argv.slice(2);
		const skipKeeper = args.includes("--skip-keeper");
		const skipMocha = args.includes("--skip-mocha");

		await Promise.all([this.runChain(), compileContractsAsync({ quiet: true })]);

		const deployments = await this.deployContracts();

		const stateManager = new StateManager(deployments);
		await stateManager.setupContracts();

		const config = await this.configureKeeper(deployments);

		console.log(config);
		if (!skipKeeper) {
			initializeManagers(config);
		} else {
			console.log("Skipping initializeManagers due to --skip-keeper flag");
		}

		if (!skipMocha) {
			// Running Mocha
			(global as any).deployments = deployments;
			const mocha = new Mocha({
				timeout: TEST_CONSTANTS.DEFAULT_TIMEOUT,
				ui: "bdd",
				reporter: "spec",
			});
			mocha.addFile(path.resolve(__dirname, "Keeper.test.ts"));
			mocha.run(failures => {
				process.exitCode = failures ? 1 : 0;
				this.teardown().then(() => {
					process.exit(process.exitCode);
				});
			});
		} else {
			console.log("Skipping Mocha tests due to --skip-mocha flag");
			await new Promise<void>(resolve => {
				this.node?.on("exit", () => {
					resolve();
				});
			});
		}
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
				ParentPool: (
					await deployParentPool(hre, {
						...deployOptions,
						args: [],
						contract: "KeeperParentPoolWrapper",
					})
				).address,
				ChildPool: (
					await deployChildPool(hre, {
						...deployOptions,
						args: [],
						contract: "KeeperChildPoolWrapper",
					})
				).address,
			};
		} finally {
			delete process.env.HARDHAT_NETWORK;
		}
	}

	private async configureKeeper(deployments: Deployment): Promise<any> {
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
			},
			// for LancaNetworkManager
			localhostNetworks: [
				{
					id: TEST_CONSTANTS.LOCALHOST_CHAIN_ID,
					name: "localhost1",
					displayName: "Localhost Chain 1",
					rpcUrls: [TEST_CONSTANTS.LOCALHOST_URL],
					chainSelector: "1",
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

const test = new KeeperIntegrationTest();
test.run();
