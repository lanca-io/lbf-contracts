import { NetworkType } from "@concero/contract-utils";
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
	minDepositQueueLength: number;
	minWithdrawalQueueLength: number;
	lurScoreSensitivity: bigint;
	lurScoreWeight: bigint;
	ndrScoreWeight: bigint;
	minDepositAmount: bigint;
	minWithdrawalAmount: bigint;
	averageConceroMessageFee: bigint;
};

type PoolFeeBps = {
	rebalancerFeeBps: number;
	lpFeeBps: number;
	lancaBridgeFeeBps: number;
};

const MINTER_ROLE = "0x9f2df0fed2c77648de5860a4cc508cd0818c85b8b8a1ab4ceeef8d981c8956a6"; // keccak256("MINTER_ROLE")
const ADDRESS_ZERO = "0x0000000000000000000000000000000000000000";
const EMPTY_BYTES = "0x0000000000000000000000000000000000000000000000000000000000000000";
const ADMIN_SLOT = "0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103";

const liqTokenDecimals = 6;

const parenPoolLiqCap = 100_000_000n * 10n ** BigInt(liqTokenDecimals);

const viemReceiptConfig: WaitForTransactionReceiptParameters = {
	timeout: 0,
	confirmations: 2,
};

const writeContractConfig: WriteContractParameters = {
	gas: 3000000n, // 3M
};

const parentPoolVariables: ParentPoolVariables = {
	minDepositQueueLength: 0,
	minWithdrawalQueueLength: 0,
	lurScoreSensitivity: 5n * 10n ** BigInt(liqTokenDecimals),
	lurScoreWeight: (7n * 10n ** BigInt(liqTokenDecimals)) / 10n,
	ndrScoreWeight: (3n * 10n ** BigInt(liqTokenDecimals)) / 10n,
	minDepositAmount: 100n * 10n ** BigInt(liqTokenDecimals),
	minWithdrawalAmount: 99n * 10n ** BigInt(liqTokenDecimals),
	averageConceroMessageFee: 0n, // TODO: set actual value
};

const poolFeeBps: PoolFeeBps = {
	rebalancerFeeBps: 5, // TODO: set actual value
	lpFeeBps: 5, // TODO: set actual value
	lancaBridgeFeeBps: 50, // TODO: set actual value
};

const parentPoolChainSelectors: Record<NetworkType, number> = {
	localhost: 1,
	testnet: 421614,
	mainnet: 42161,
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
	childPoolProxy: "CHILD_POOL_PROXY",
	childPoolProxyAdmin: "CHILD_POOL_PROXY_ADMIN",
	create3Factory: "CREATE3_FACTORY",
	pause: "CONCERO_PAUSE",
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
	PoolFeeBps,
	poolFeeBps,
	MINTER_ROLE,
	liqTokenDecimals,
	parenPoolLiqCap,
	ADDRESS_ZERO,
	EMPTY_BYTES,
	ADMIN_SLOT,
};
