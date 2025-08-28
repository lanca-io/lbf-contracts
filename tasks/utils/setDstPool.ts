import { getNetworkEnvKey } from "@concero/contract-utils";

import { conceroNetworks } from "../../constants";
import { getEnvVar, getFallbackClients, getViemAccount, log } from "../../utils";

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

	const viemAccount = getViemAccount(srcChain.type, "deployer");
	const { walletClient, publicClient } = getFallbackClients(srcChain, viemAccount);

	let srcPoolProxyAddress: string | undefined;
	let dstPoolProxyAddress: string | undefined;

	if (srcChainName === "arbitrum" || srcChainName === "arbitrumSepolia") {
		srcPoolProxyAddress = getEnvVar(`PARENT_POOL_PROXY_${getNetworkEnvKey(srcChainName)}`);
		dstPoolProxyAddress = getEnvVar(`CHILD_POOL_PROXY_${getNetworkEnvKey(dstChainName)}`);
	} else if (dstChainName === "arbitrum" || dstChainName === "arbitrumSepolia") {
		srcPoolProxyAddress = getEnvVar(`CHILD_POOL_PROXY_${getNetworkEnvKey(srcChainName)}`);
		dstPoolProxyAddress = getEnvVar(`PARENT_POOL_PROXY_${getNetworkEnvKey(dstChainName)}`);
	} else {
		srcPoolProxyAddress = getEnvVar(`CHILD_POOL_PROXY_${getNetworkEnvKey(srcChainName)}`);
		dstPoolProxyAddress = getEnvVar(`CHILD_POOL_PROXY_${getNetworkEnvKey(dstChainName)}`);
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

		if (currentDstPool !== dstPoolProxyAddress) {
			const setDstPoolHash = await walletClient.writeContract({
				address: srcPoolProxyAddress,
				abi: parentPoolAbi,
				functionName: "setDstPool",
				args: [dstChainSelector, dstPoolProxyAddress],
			});

			log(
				`Set destination pool for ${srcChainName} to ${dstChainName}, hash: ${setDstPoolHash}`,
				"setDstPool",
				srcChainName,
			);
		} else {
			log(
				`Destination pool already set for ${srcChainName} to ${dstChainName}`,
				"setDstPool",
				srcChainName,
			);
		}
	} catch (error) {
		log(
			`Failed to set destination pool for ${srcChainName} to ${dstChainName}: ${error.message}`,
			"setDstPool",
			srcChainName,
		);
	}
}
