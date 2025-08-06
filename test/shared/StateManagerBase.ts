import {
	PublicActions,
	TestClient,
	WalletActions,
	createTestClient,
	http,
	publicActions,
	walletActions,
} from "viem";
import { parseEther } from "viem";

import MockERC20Artifact from "../../artifacts/contracts/MockERC20/MockERC20.sol/MockERC20.json";

const deployer = process.env.LOCALHOST_DEPLOYER_ADDRESS as `0x${string}`;

export interface Deployment {
	ParentPool: string;
	ChildPool: string;
	USDC: string;
	LPToken?: string;
	IOUToken?: string;
}

export interface TestConstants {
	LOCALHOST_URL: string;
	DEFAULT_ETH_BALANCE: string;
	EVENT_POLLING_INTERVAL_MS: number;
}

export class StateManagerBase {
	protected testClient: TestClient & PublicActions & WalletActions;
	protected deployments: Deployment;

	constructor(deployments: Deployment, testConstants: TestConstants) {
		this.deployments = deployments;

		this.testClient = createTestClient({
			chain: {
				id: 1,
				name: "Localhost",
				network: "localhost",
				nativeCurrency: {
					name: "Ether",
					symbol: "ETH",
					decimals: 18,
				},
				rpcUrls: {
					default: {
						http: [testConstants.LOCALHOST_URL],
					},
					public: {
						http: [testConstants.LOCALHOST_URL],
					},
				},
			},
			mode: "hardhat",
			transport: http(testConstants.LOCALHOST_URL),
			account: deployer,
		})
			.extend(publicActions)
			.extend(walletActions);
	}

	async getBalance(address: `0x${string}`): Promise<bigint> {
		return await this.testClient.getBalance({ address });
	}

	async getTokenBalance(tokenAddress: `0x${string}`, address: `0x${string}`): Promise<bigint> {
		return (await this.testClient.readContract({
			address: tokenAddress,
			abi: MockERC20Artifact.abi,
			functionName: "balanceOf",
			args: [address],
		})) as bigint;
	}

	async readAllowance(
		tokenAddress: `0x${string}`,
		owner: `0x${string}`,
		spender: `0x${string}`,
	): Promise<bigint> {
		return (await this.testClient.readContract({
			address: tokenAddress,
			abi: MockERC20Artifact.abi,
			functionName: "allowance",
			args: [owner, spender],
		})) as bigint;
	}

	async setAllowance(
		tokenAddress: `0x${string}`,
		owner: `0x${string}`,
		spender: `0x${string}`,
		amount: bigint,
	): Promise<void> {
		await this.testClient.impersonateAccount({ address: owner });
		await this.testClient.writeContract({
			address: tokenAddress,
			abi: MockERC20Artifact.abi,
			functionName: "approve",
			args: [spender, amount],
			account: owner,
		});
	}

	createEventListener<T extends string>(
		contractAddress: `0x${string}`,
		abi: any[],
		eventName: T,
		callback: (event: any) => void,
		pollingInterval?: number,
	) {
		return this.testClient.watchContractEvent({
			address: contractAddress,
			abi,
			eventName,
			onLogs: callback,
			pollingInterval: pollingInterval || 100,
		});
	}

	async waitForEvent<T extends string>(
		contractAddress: `0x${string}`,
		abi: any[],
		eventName: T,
		timeoutMs: number,
		pollingInterval?: number,
	): Promise<any> {
		return new Promise((resolve, reject) => {
			const timeout = setTimeout(() => {
				unwatch();
				reject(new Error(`Timeout waiting for ${eventName} event`));
			}, timeoutMs);

			const unwatch = this.createEventListener(
				contractAddress,
				abi,
				eventName,
				logs => {
					clearTimeout(timeout);
					unwatch();
					resolve({
						logs: logs.map((log: any) => ({
							eventName: log.eventName,
							args: log.args,
							...log,
						})),
					});
				},
				pollingInterval,
			);
		});
	}

	async mintTokens(
		tokenAddress: `0x${string}`,
		to: `0x${string}`,
		amount: bigint,
	): Promise<void> {
		await this.testClient.writeContract({
			address: tokenAddress,
			abi: MockERC20Artifact.abi,
			functionName: "mint",
			args: [to, amount],
			account: deployer,
		});
	}

	async burnTokens(
		tokenAddress: `0x${string}`,
		from: `0x${string}`,
		amount: bigint,
	): Promise<void> {
		await this.testClient.writeContract({
			address: tokenAddress,
			abi: MockERC20Artifact.abi,
			functionName: "burn",
			args: [from, amount],
			account: deployer,
		});
	}

	async setTokenBalance(
		tokenAddress: `0x${string}`,
		targetAddress: `0x${string}`,
		newBalance: bigint,
	): Promise<void> {
		const currentBalance = await this.getTokenBalance(tokenAddress, targetAddress);
		const diff = newBalance - currentBalance;

		if (diff > 0n) {
			await this.mintTokens(tokenAddress, targetAddress, diff);
		} else if (diff < 0n) {
			await this.burnTokens(tokenAddress, targetAddress, -diff);
		}
	}

	async advanceBlocks(blocks: number): Promise<void> {
		await this.testClient.mine({ blocks });
	}

	async advanceTime(seconds: number): Promise<void> {
		await this.testClient.increaseTime({ seconds });
		await this.testClient.mine({ blocks: 1 });
	}

	async getTestAccounts(): Promise<`0x${string}`[]> {
		const accounts = await this.testClient.getAddresses();
		return accounts as `0x${string}`[];
	}

	async setEthBalance(address: `0x${string}`, balance: string): Promise<void> {
		await this.testClient.setBalance({
			address,
			value: parseEther(balance),
		});
	}
}
