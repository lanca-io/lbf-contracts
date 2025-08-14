import { getNetworkEnvKey } from "@concero/contract-utils";

import { conceroNetworks } from "../../constants";
import { getFallbackClients, getViemAccount, log } from "../../utils";
import { getEnvVar } from "../../utils";

export async function setDstPool(srcChainName: string, dstChainName: string) {
	const chain = conceroNetworks[srcChainName as keyof typeof conceroNetworks];

	const viemAccount = getViemAccount(chain.type, "deployer");
	const { walletClient, publicClient } = getFallbackClients(chain, viemAccount);

	let srcPoolProxyAddress: string | undefined;
	let dstPoolProxyAddress: string | undefined;

	if (chain.name === "arbitrum" || chain.name === "arbitrumSepolia") {
		srcPoolProxyAddress = getEnvVar(`PARENT_POOL_PROXY_${getNetworkEnvKey(srcChainName)}`);
		dstPoolProxyAddress = getEnvVar(`PARENT_POOL_PROXY_${getNetworkEnvKey(dstChainName)}`);
	} else {
		srcPoolProxyAddress = getEnvVar(`CHILD_POOL_PROXY_${getNetworkEnvKey(srcChainName)}`);
		dstPoolProxyAddress = getEnvVar(`CHILD_POOL_PROXY_${getNetworkEnvKey(dstChainName)}`);
	}

	if (!srcPoolProxyAddress || !dstPoolProxyAddress) {
		throw new Error(
			`Missing required Pool proxy address for ${srcChainName} or ${dstChainName}`,
		);
	}

	const { abi: parentPoolAbi } = await import(
		"../../artifacts/contracts/ParentPool/ParentPool.sol/ParentPool.json"
	);

	try {
		const setDstPoolHash = await walletClient.writeContract({
			address: srcPoolProxyAddress,
			abi: parentPoolAbi,
			functionName: "setDstPool",
			args: [dstPoolProxyAddress],
		});

		log(
			`Set destination pool for ${srcChainName} to ${dstChainName}, hash: ${setDstPoolHash}`,
			"setDstPool",
			srcChainName,
		);
	} catch (error) {
		log(
			`Failed to set destination pool for ${srcChainName} to ${dstChainName}: ${error.message}`,
			"setDstPool",
			srcChainName,
		);
	}
}
