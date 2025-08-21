import { getNetworkEnvKey } from "@concero/contract-utils";

import { conceroNetworks } from "../../constants";
import { accessControlAbi } from "../../constants/accessControlAbi";
import { MINTER_ROLE } from "../../constants/deploymentVariables";
import { getFallbackClients, getViemAccount, log } from "../../utils";
import { getEnvVar } from "../../utils";

export async function grantMinterRoleForLPToken(networkName: string) {
	const chain = conceroNetworks[networkName as keyof typeof conceroNetworks];

	const viemAccount = getViemAccount(chain.type, "deployer");
	const { walletClient, publicClient } = getFallbackClients(chain, viemAccount);

	const parentPoolProxyAddress = getEnvVar(
		`PARENT_POOL_PROXY_${getNetworkEnvKey(networkName)}` as keyof typeof process.env,
	);
	const lpTokenAddress = getEnvVar(
		`LPT_${getNetworkEnvKey(networkName)}` as keyof typeof process.env,
	);

	if (!parentPoolProxyAddress || !lpTokenAddress) {
		throw new Error(`Missing ParentPool or LPToken proxy address for ${networkName}`);
	}

	try {
		const hasRole = await publicClient.readContract({
			address: lpTokenAddress as `0x${string}`,
			abi: accessControlAbi,
			functionName: "hasRole",
			args: [MINTER_ROLE as `0x${string}`, parentPoolProxyAddress as `0x${string}`],
		});

		if (hasRole) {
			log(
				`ParentPool already has MINTER_ROLE on LPToken`,
				"grantMinterRoleForLPToken",
				networkName,
			);
			return;
		}

		const grantRoleHash = await walletClient.writeContract({
			address: lpTokenAddress,
			abi: accessControlAbi,
			functionName: "grantRole",
			args: [MINTER_ROLE as `0x${string}`, parentPoolProxyAddress as `0x${string}`],
			account: viemAccount,
			chain: chain.viemChain,
		});

		log(
			`Successfully granted MINTER_ROLE to ParentPool (${parentPoolProxyAddress}) on LPToken (${lpTokenAddress}), hash: ${grantRoleHash}`,
			"grantMinterRoleForLPToken",
			networkName,
		);
	} catch (error) {
		log(
			`Failed to grant MINTER_ROLE to ParentPool on LPToken: ${error instanceof Error ? error.message : String(error)}`,
			"grantMinterRoleForLPToken",
			networkName,
		);
		throw error;
	}
}
