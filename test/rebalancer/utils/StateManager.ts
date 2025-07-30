import { toUtf8Bytes } from "ethers";

import {
	PublicActions,
	TestClient,
	WalletActions,
	createTestClient,
	defineChain,
	http,
	publicActions,
	walletActions,
} from "viem";
import { getAbiItem } from "viem";
import { parseEther, toHex } from "viem";
import { keccak256 } from "viem";

import ChildPoolArtifact from "../../../artifacts/contracts/ChildPool/ChildPool.sol/ChildPool.json";
import MockERC20Artifact from "../../../artifacts/contracts/MockERC20/MockERC20.sol/MockERC20.json";
import LPTokenArtifact from "../../../artifacts/contracts/ParentPool/LPToken.sol/LPToken.json";
import ParentPoolArtifact from "../../../artifacts/contracts/ParentPool/ParentPool.sol/ParentPool.json";
import IOUTokenArtifact from "../../../artifacts/contracts/Rebalancer/IOUToken.sol/IOUToken.json";
import ParentPoolWrapperArtifact from "../../../artifacts/contracts/test-helpers/ParentPoolWrapper.sol/ParentPoolWrapper.json";
import { ROLE_CONSTANTS, TEST_CONSTANTS } from "../constants";
import { Deployment } from "../test";
import { localhostViemChain } from "./localhostViemChain";

const deployer = process.env.LOCALHOST_DEPLOYER_ADDRESS;
const operator = process.env.OPERATOR_ADDRESS;
export interface PoolState {
	activeBalance: bigint;
	targetBalance: bigint;
	currentDeficit: bigint;
	currentSurplus: bigint;
}

export class StateManager {
	private testClient: TestClient & PublicActions & WalletActions;
	private deployments: Deployment;

	constructor(deployments: Deployment) {
		this.deployments = deployments;

		this.testClient = createTestClient({
			chain: localhostViemChain,
			mode: "hardhat",
			transport: http(TEST_CONSTANTS.LOCALHOST_URL),
			account: deployer,
		})
			.extend(publicActions)
			.extend(walletActions);
	}

	async setupContracts(): Promise<void> {
		const MINTER_ROLE = keccak256(toUtf8Bytes(ROLE_CONSTANTS.MINTER_ROLE));

		await this.testClient.setBalance({
			address: deployer,
			value: parseEther(TEST_CONSTANTS.DEFAULT_ETH_BALANCE),
		});

		await this.testClient.writeContract({
			address: this.deployments.IOUToken,
			abi: IOUTokenArtifact.abi,
			functionName: "grantRole",
			args: [MINTER_ROLE, deployer],
			account: deployer,
		});

		await this.testClient.writeContract({
			address: this.deployments.LPToken,
			abi: LPTokenArtifact.abi,
			functionName: "grantRole",
			args: [MINTER_ROLE, deployer],
			account: deployer,
		});
	}

	async getPoolState(poolAddress: `0x${string}`): Promise<PoolState> {
		const poolAbi =
			poolAddress === this.deployments.ParentPool
				? ParentPoolArtifact.abi
				: ChildPoolArtifact.abi;

		const [activeBalance, targetBalance, currentDeficit, currentSurplus] = await Promise.all([
			this.testClient.readContract({
				address: poolAddress,
				abi: poolAbi,
				functionName: "getActiveBalance",
			}),
			this.testClient.readContract({
				address: poolAddress,
				abi: poolAbi,
				functionName: "getTargetBalance",
			}),
			this.testClient.readContract({
				address: poolAddress,
				abi: poolAbi,
				functionName: "getCurrentDeficit",
			}),
			this.testClient.readContract({
				address: poolAddress,
				abi: poolAbi,
				functionName: "getCurrentSurplus",
			}),
		]);

		return {
			activeBalance,
			targetBalance,
			currentDeficit,
			currentSurplus,
		};
	}

	async setTokenBalance(
		tokenAddress: `0x${string}`,
		targetAddress: `0x${string}`,
		newBalance: bigint,
	): Promise<void> {
		const currentBalance = await this.testClient.readContract({
			address: tokenAddress,
			abi: MockERC20Artifact.abi,
			functionName: "balanceOf",
			args: [targetAddress],
		});

		const diff = newBalance - currentBalance;

		if (diff > 0n) {
			await this.mintTokens(tokenAddress, targetAddress, diff);
		} else if (diff < 0n) {
			await this.burnTokens(tokenAddress, targetAddress, -diff);
		}
	}

	async mintTokens(
		tokenAddress: `0x${string}`,
		to: `0x${string}`,
		amount: bigint,
	): Promise<void> {
		const mintFunction = getAbiItem({ abi: MockERC20Artifact.abi, name: "mint" });

		if (mintFunction) {
			// Use test client to impersonate and mint
			await this.testClient.setBalance({
				address: to,
				value: parseEther(TEST_CONSTANTS.DEFAULT_ETH_BALANCE),
				account: deployer,
			});

			await this.testClient.writeContract({
				address: tokenAddress,
				abi: MockERC20Artifact.abi,
				functionName: "mint",
				args: [to, amount],
				account: deployer,
			});
		}
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
			account: from,
		});
	}

	async setStorageAt(
		contractAddress: `0x${string}`,
		slot: `0x${string}`,
		value: `0x${string}`,
	): Promise<void> {
		await this.testClient.setStorageAt({
			address: contractAddress,
			index: slot,
			value: value,
			account: deployer,
		});
	}

	async setTargetBalance(poolAddress: `0x${string}`, newTargetBalance: bigint): Promise<void> {
		await this.testClient.writeContract({
			address: poolAddress,
			abi: ParentPoolWrapperArtifact.abi,
			functionName: "setTargetBalance",
			args: [newTargetBalance],
			account: deployer,
		});
	}

	async createDeficitState(poolAddress: `0x${string}`, deficitAmount: bigint): Promise<void> {
		const currentState = await this.getPoolState(poolAddress);
		const newTargetBalance = currentState.activeBalance + deficitAmount;

		await this.setTargetBalance(poolAddress, newTargetBalance);
	}

	async createSurplusState(poolAddress: `0x${string}`, surplusAmount: bigint): Promise<void> {
		const currentState = await this.getPoolState(poolAddress);
		const newTargetBalance = currentState.activeBalance - surplusAmount;

		await this.setTargetBalance(poolAddress, newTargetBalance);
	}

	async transferTokens(
		tokenAddress: `0x${string}`,
		from: `0x${string}`,
		to: `0x${string}`,
		amount: bigint,
	): Promise<void> {
		await this.testClient.setBalance({
			address: from,
			value: parseEther(TEST_CONSTANTS.DEFAULT_NATIVE_TRANSFER),
			account: deployer,
		});

		await this.testClient.writeContract({
			address: tokenAddress,
			abi: MockERC20Artifact.abi,
			functionName: "approve",
			args: [from, amount],
			account: from,
		});

		await this.testClient.writeContract({
			address: tokenAddress,
			abi: MockERC20Artifact.abi,
			functionName: "transferFrom",
			args: [from, to, amount],
			account: from,
		});
	}

	async sendNativeValue(to: `0x${string}`, amount: bigint): Promise<void> {
		await this.testClient.setBalance({
			address: to,
			value: amount,
		});
	}

	async advanceBlocks(blocks: number): Promise<void> {
		await this.testClient.mine({ blocks });
	}

	async advanceTime(seconds: number): Promise<void> {
		await this.testClient.increaseTime({ seconds });
		await this.testClient.mine({ blocks: 1 });
	}

	async getBalance(address: `0x${string}`): Promise<bigint> {
		return await this.testClient.getBalance({ address });
	}

	async getTokenBalance(tokenAddress: `0x${string}`, address: `0x${string}`): Promise<bigint> {
		return await this.testClient.readContract({
			address: tokenAddress,
			abi: MockERC20Artifact.abi,
			functionName: "balanceOf",
			args: [address],
		});
	}

	createEventListener(
		poolAddress: `0x${string}`,
		eventName: "DeficitFilled" | "SurplusTaken",
		callback: (event: any) => void,
	) {
		const poolAbi =
			poolAddress === this.deployments.ParentPool
				? ParentPoolArtifact.abi
				: ChildPoolArtifact.abi;

		return this.testClient.watchContractEvent({
			address: poolAddress,
			abi: poolAbi,
			eventName,
			onLogs: callback,
		});
	}

	async waitForRebalancerEvent(
		poolAddress: `0x${string}`,
		eventName: "DeficitFilled" | "SurplusTaken",
		timeoutMs: number = 30000,
	): Promise<any> {
		return new Promise((resolve, reject) => {
			const timeout = setTimeout(() => {
				unwatch();
				reject(new Error(`Timeout waiting for ${eventName} event`));
			}, timeoutMs);

			const unwatch = this.createEventListener(poolAddress, eventName, event => {
				clearTimeout(timeout);
				unwatch();
				resolve(event);
			});
		});
	}

	async waitForBalancedState(
		poolAddress: `0x${string}`,
		maxWaitMs: number = 60000,
	): Promise<void> {
		const startTime = Date.now();
		while (Date.now() - startTime < maxWaitMs) {
			const state = await this.getPoolState(poolAddress);
			if (state.currentDeficit === 0n && state.currentSurplus === 0n) {
				return;
			}
			await new Promise(resolve => setTimeout(resolve, TEST_CONSTANTS.BLOCK_CHECK_INTERVAL));
		}
		throw new Error("Timeout waiting for balanced state");
	}

	async getTestAccounts(): Promise<`0x${string}`[]> {
		const accounts = await this.testClient.getAddresses();
		return accounts as `0x${string}`[];
	}
}
