import { getNetworkEnvKey } from "@concero/contract-utils";

import { conceroNetworks } from "../../constants";
import { parenPoolLiqCap } from "../../constants/deploymentVariables";
import { getEnvVar, getFallbackClients, getViemAccount, log } from "../../utils";

export async function setParentPoolLiqCap(name: string) {
	const chain = conceroNetworks[name as keyof typeof conceroNetworks];
	const viemAccount = getViemAccount(chain.type, "deployer");
	const { walletClient, publicClient } = getFallbackClients(chain, viemAccount);

	const parentPoolProxyAddress = getEnvVar(`PARENT_POOL_PROXY_${getNetworkEnvKey(name)}`);

	if (!parentPoolProxyAddress) {
		throw new Error("Missing required addresses for setting variables");
	}

	const { abi: parentPoolAbi } = await import(
		"../../artifacts/contracts/ParentPool/ParentPool.sol/ParentPool.json"
	);

	try {
		const currentLiqCap = await publicClient.readContract({
			address: parentPoolProxyAddress,
			abi: parentPoolAbi,
			functionName: "getLiquidityCap",
		});

		if (currentLiqCap !== parenPoolLiqCap) {
			const setTargetDepositQueueLength = await walletClient.writeContract({
				address: parentPoolProxyAddress,
				abi: parentPoolAbi,
				functionName: "setLiquidityCap",
				args: [parenPoolLiqCap],
			});

			log(
				`Set parent pool liq cap to ${parenPoolLiqCap}, hash: ${setTargetDepositQueueLength}`,
				"setLiquidityCap",
				name,
			);
		} else {
			log(`Parent pool liq cap already set to ${parenPoolLiqCap}`, "setLiquidityCap", name);
		}
	} catch (error) {
		log(`Failed to set target deposit queue length: ${error.message}`, "setLiquidityCap", name);
	}
}
