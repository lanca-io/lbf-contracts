import { getNetworkEnvKey } from "@concero/contract-utils";

import { conceroNetworks } from "../../constants";
import { getEnvVar, getFallbackClients, getViemAccount, log } from "../../utils";

export async function setLancaKeeper(networkName: string) {
	const chain = conceroNetworks[networkName as keyof typeof conceroNetworks];

	const viemAccount = getViemAccount(chain.type, "deployer");
	const { walletClient, publicClient } = getFallbackClients(chain, viemAccount);

	let poolAddress: string | undefined;
	let poolType: string;

	if (
		networkName === "arbitrjum" ||
		networkName === "arbitrumSepolia" ||
		networkName === "localhost"
	) {
		poolAddress = getEnvVar(`PARENT_POOL_PROXY_${getNetworkEnvKey(networkName)}`);
		poolType = "ParentPool";
	} else {
		poolAddress = getEnvVar(`CHILD_POOL_PROXY_${getNetworkEnvKey(networkName)}`);
		poolType = "ChildPool";
	}

	if (!poolAddress) {
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
		const currentLancaKeeper = await publicClient.readContract({
			address: poolAddress,
			abi: parentPoolAbi,
			functionName: "getLancaKeeper",
			args: [],
		});

		if (currentLancaKeeper.toLowerCase() !== keeperAddress.toLowerCase()) {
			const setLancaKeeperHash = await walletClient.writeContract({
				address: poolAddress,
				abi: parentPoolAbi,
				functionName: "setLancaKeeper",
				args: [keeperAddress],
			});

			log(
				`Set LancaKeeper for ${poolType} on ${networkName} to ${keeperAddress}, hash: ${setLancaKeeperHash}`,
				"setLancaKeeper",
				networkName,
			);
		} else {
			log(
				`LancaKeeper for ${poolType} on ${networkName} already set to ${keeperAddress}`,
				"setLancaKeeper",
				networkName,
			);
		}
	} catch (error) {
		log(
			`Failed to set LancaKeeper for ${poolType} on ${networkName}: ${error.message}`,
			"setLancaKeeper",
			networkName,
		);
	}
}
