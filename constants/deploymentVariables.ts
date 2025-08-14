import { NetworkType } from "@concero/contract-utils/dist/types";
import { WriteContractParameters } from "viem";
import type { WaitForTransactionReceiptParameters } from "viem/actions/public/waitForTransactionReceipt";

import { ConceroNetwork } from "../types/ConceroNetwork";
import { EnvPrefixes } from "../types/deploymentVariables";

enum ProxyEnum {
	routerProxy = "routerProxy",
	verifierProxy = "verifierProxy",
	parentPoolProxy = "parentPoolProxy",
	childPoolProxy = "childPoolProxy",
}

type ParentPoolVariables = {
	targetDepositQueueLength: number;
	targetWithdrawalQueueLength: number;
	lurScoreSensitivity: bigint;
	lurScoreWeight: bigint;
	ndrScoreWeight: bigint;
};

const MINTER_ROLE = "0x9f2df0fed2c77648de5860a4cc508cd0818c85b8b8a1ab4ceeef8d981c8956a6"; // keccak256("MINTER_ROLE")

const viemReceiptConfig: WaitForTransactionReceiptParameters = {
	timeout: 0,
	confirmations: 2,
};

const writeContractConfig: WriteContractParameters = {
	gas: 3000000n, // 3M
};

const parentPoolVariables: ParentPoolVariables = {
	targetDepositQueueLength: 100,
	targetWithdrawalQueueLength: 100,
	lurScoreSensitivity: 2000000n,
	lurScoreWeight: 500000n,
	ndrScoreWeight: 500000n,
};

function getViemReceiptConfig(chain: ConceroNetwork): Partial<WaitForTransactionReceiptParameters> {
	return {
		timeout: 0,
		confirmations: chain.confirmations,
	};
}

const envPrefixes: EnvPrefixes = {
	router: "CONCERO_ROUTER",
	routerProxy: "CONCERO_ROUTER_PROXY",
	routerProxyAdmin: "CONCERO_ROUTER_PROXY_ADMIN",
	verifier: "CONCERO_VERIFIER",
	verifierProxy: "CONCERO_VERIFIER_PROXY",
	verifierProxyAdmin: "CONCERO_VERIFIER_PROXY_ADMIN",
	parentPool: "PARENT_POOL",
	parentPoolProxy: "PARENT_POOL_PROXY",
	parentPoolProxyAdmin: "PARENT_POOL_PROXY_ADMIN",
	lpToken: "LPTOKEN",
	iouToken: "IOUTOKEN",
	childPool: "CHILD_POOL",
	create3Factory: "CREATE3_FACTORY",
	pause: "CONCERO_PAUSE",
};

const parentPoolChainSelectors: Record<NetworkType, number> = {
	localhost: 1,
	testnet: 421614,
	mainnet: 42161,
};

export {
	viemReceiptConfig,
	writeContractConfig,
	ProxyEnum,
	envPrefixes,
	getViemReceiptConfig,
	parentPoolChainSelectors,
	ParentPoolVariables,
	parentPoolVariables,
	MINTER_ROLE,
};
