import { getNetworkEnvKey } from "@concero/contract-utils";
import { pad } from "viem";

import { conceroNetworks } from "../../constants";
import { err, getEnvVar, getFallbackClients, getViemAccount, log, warn } from "../../utils";
import { isParentPoolNetwork } from "./isParentPoolNetwork";

export async function setDstPool(srcChainName: string, dstChainName: string) {
	const srcChain = conceroNetworks[srcChainName as keyof typeof conceroNetworks];
	const dstChain = conceroNetworks[dstChainName as keyof typeof conceroNetworks];

	if (!srcChain || !dstChain) {
		throw new Error(`Chain ${srcChainName} or ${dstChainName} not found`);
	}

	if (srcChain.name === dstChain.name) {
		throw new Error("Source and destination chains cannot be the same");
	}

	const dstChainSelector = dstChain.chainSelector;

	if (!dstChainName) {
		throw new Error("Missing destination chain name");
	}

	const viemAccount = getViemAccount(srcChain.type, "proxyDeployer");
	const { walletClient, publicClient } = getFallbackClients(srcChain, viemAccount);

	const parentPoolPrefix = "PARENT_POOL_PROXY_";
	const childPoolPrefix = "CHILD_POOL_PROXY_";

	const srcPoolProxyAddress = getEnvVar(
		`${isParentPoolNetwork(srcChainName) ? parentPoolPrefix : childPoolPrefix}${getNetworkEnvKey(srcChainName)}`,
	);
	const dstPoolProxyAddress = getEnvVar(
		`${isParentPoolNetwork(dstChainName) ? parentPoolPrefix : childPoolPrefix}${getNetworkEnvKey(dstChainName)}`,
	);

	if (!srcPoolProxyAddress) {
		console.warn(`Missing required Pool proxy address for ${srcChainName}`);
		return;
	}

	if (!dstPoolProxyAddress) {
		console.warn(`Missing required Pool proxy address for ${dstChainName}`);
		return;
	}

	const { abi: parentPoolAbi } = await import(
		"../../artifacts/contracts/ParentPool/ParentPool.sol/ParentPool.json"
	);

	try {
		const currentDstPool = await publicClient.readContract({
			address: srcPoolProxyAddress,
			abi: parentPoolAbi,
			functionName: "getDstPool",
			args: [dstChainSelector],
		});
		const dstPoolProxyBytes32 = pad(dstPoolProxyAddress as `0x${string}`, {
			size: 32,
			dir: "right",
		});

		if (currentDstPool !== dstPoolProxyBytes32) {
			const setDstPoolHash = await walletClient.writeContract({
				address: srcPoolProxyAddress,
				abi: parentPoolAbi,
				functionName: "setDstPool",
				args: [dstChainSelector, dstPoolProxyBytes32],
			});

			log(
				`Set destination pool for ${srcChainName} to ${dstChainName}, hash: ${setDstPoolHash}`,
				"setDstPool",
				srcChainName,
			);
		} else {
			warn(
				`Destination pool already set for ${srcChainName} to ${dstChainName}`,
				"setDstPool",
			);
		}
	} catch (error) {
		err(
			`Failed to set destination pool for ${srcChainName} to ${dstChainName}: ${error.message}`,
			"setDstPool",
			srcChainName,
		);
	}
}
