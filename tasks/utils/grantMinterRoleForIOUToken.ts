import { getNetworkEnvKey } from "@concero/contract-utils";

import { conceroNetworks } from "../../constants";
import { accessControlAbi } from "../../constants/accessControlAbi";
import { MINTER_ROLE } from "../../constants/deploymentVariables";
import { getFallbackClients, getViemAccount, log } from "../../utils";
import { getEnvVar } from "../../utils";

export async function grantMinterRoleForIOUToken(networkName: string) {
	const chain = conceroNetworks[networkName as keyof typeof conceroNetworks];

	const viemAccount = getViemAccount(chain.type, "deployer");
	const { walletClient, publicClient } = getFallbackClients(chain, viemAccount);

	let poolProxyAddress: string | undefined;
	let poolPrefix: string;

	if (
		networkName === "arbitrum" ||
		networkName === "arbitrumSepolia" ||
		networkName === "localhost"
	) {
		poolProxyAddress = getEnvVar(`PARENT_POOL_PROXY_${getNetworkEnvKey(networkName)}`);
		poolPrefix = "Parent";
	} else {
		poolProxyAddress = getEnvVar(`CHILD_POOL_PROXY_${getNetworkEnvKey(networkName)}`);
		poolPrefix = "Child";
	}

	const iouTokenAddress = getEnvVar(`IOU_${getNetworkEnvKey(networkName)}`);

	if (!poolProxyAddress || !iouTokenAddress) {
		throw new Error(`Missing ${poolPrefix}Pool or IOUToken proxy address for ${networkName}`);
	}

	try {
		const hasRole = await publicClient.readContract({
			address: iouTokenAddress as `0x${string}`,
			abi: accessControlAbi,
			functionName: "hasRole",
			args: [MINTER_ROLE as `0x${string}`, poolProxyAddress as `0x${string}`],
		});

		if (hasRole) {
			log(
				`${poolPrefix}Pool already has MINTER_ROLE on IOUToken`,
				"grantMinterRoleForIOUToken",
				networkName,
			);
			return;
		}

		const grantRoleHash = await walletClient.writeContract({
			address: iouTokenAddress,
			abi: accessControlAbi,
			functionName: "grantRole",
			args: [MINTER_ROLE as `0x${string}`, poolProxyAddress as `0x${string}`],
			account: viemAccount,
			chain: chain.viemChain,
		});

		log(
			`Successfully granted MINTER_ROLE to ${poolPrefix}Pool (${poolProxyAddress}) on IOUToken (${iouTokenAddress}), hash: ${grantRoleHash}`,
			"grantMinterRoleForIOUToken",
			networkName,
		);
	} catch (error) {
		log(
			`Failed to grant MINTER_ROLE to ${poolPrefix}Pool on IOUToken: ${error instanceof Error ? error.message : String(error)}`,
			"grantMinterRoleForIOUToken",
			networkName,
		);
		throw error;
	}
}
