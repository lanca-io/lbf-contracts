import { getNetworkEnvKey } from "@concero/contract-utils";

import { conceroNetworks } from "../../constants";
import { getFallbackClients, getViemAccount, log } from "../../utils";
import { getEnvVar } from "../../utils";

export async function setLancaKeeper(networkName: string) {
	const chain = conceroNetworks[networkName as keyof typeof conceroNetworks];

	const viemAccount = getViemAccount(chain.type, "deployer");
	const { walletClient, publicClient } = getFallbackClients(chain, viemAccount);

	let poolProxyAddress: string | undefined;
	let poolType: string;

	if (
		networkName === "arbitrum" ||
		networkName === "arbitrumSepolia" ||
		networkName === "localhost"
	) {
		poolProxyAddress = getEnvVar(`PARENT_POOL_PROXY_${getNetworkEnvKey(networkName)}`);
		poolType = "ParentPool";
	} else {
		poolProxyAddress = getEnvVar(`CHILD_POOL_PROXY_${getNetworkEnvKey(networkName)}`);
		poolType = "ChildPool";
	}

	if (!poolProxyAddress) {
		throw new Error(`Missing ${poolType} proxy address for ${networkName}`);
	}

	const keeperAddress = getEnvVar(`LANCA_KEEPER`);

	if (!keeperAddress) {
		throw new Error("Missing keeper address");
	}

	const { abi: parentPoolAbi } = await import(
		"../../artifacts/contracts/ParentPool/ParentPool.sol/ParentPool.json"
	);

	try {
		const setLancaKeeperHash = await walletClient.writeContract({
			address: poolProxyAddress,
			abi: parentPoolAbi,
			functionName: "setLancaKeeper",
			args: [keeperAddress],
			account: viemAccount,
			chain: chain.viemChain,
		});

		log(
			`Set LancaKeeper for ${poolType} on ${networkName} to ${keeperAddress}, hash: ${setLancaKeeperHash}`,
			"setLancaKeeper",
			networkName,
		);
	} catch (error) {
		log(
			`Failed to set LancaKeeper for ${poolType} on ${networkName}: ${error.message}`,
			"setLancaKeeper",
			networkName,
		);
	}
}
