import { HardhatRuntimeEnvironment } from "hardhat/types";

import { ProxyEnum, conceroNetworks } from "../../constants";
import { EnvPrefixes, IProxyType } from "../../types/deploymentVariables";
import { err, getEnvAddress, getFallbackClients, getViemAccount, log } from "../../utils";

export async function upgradeProxyImplementation(
	hre: HardhatRuntimeEnvironment,
	proxyType: IProxyType,
	shouldPause: boolean,
) {
	const { name } = hre.network;
	const chain = conceroNetworks[name as keyof typeof conceroNetworks];
	const { viemChain, type } = chain;

	let implementationKey: keyof EnvPrefixes;

	if (shouldPause) {
		implementationKey = "pause";
	} else if (proxyType === ProxyEnum.parentPoolProxy) {
		implementationKey = "parentPool";
	} else if (proxyType === ProxyEnum.childPoolProxy) {
		implementationKey = "childPool";
	} else {
		err(`Proxy type ${proxyType} not found`, "upgradeProxyImplementation", name);
		return;
	}

	const { abi: proxyAdminAbi } = hre.artifacts.readArtifactSync("ProxyAdmin");

	const viemAccount = getViemAccount(type, "deployer");
	const { walletClient } = getFallbackClients(chain, viemAccount);

	const [conceroProxy, conceroProxyAlias] = getEnvAddress(proxyType as keyof EnvPrefixes, name);
	const [proxyAdmin, proxyAdminAlias] = getEnvAddress(
		`${proxyType}Admin` as keyof EnvPrefixes,
		name,
	);
	const [newImplementation, newImplementationAlias] = getEnvAddress(implementationKey, name);

	const implementation = shouldPause ? getEnvAddress("pause", name)[0] : newImplementation;
	const implementationAlias = shouldPause
		? getEnvAddress("pause", name)[1]
		: newImplementationAlias;

	const txHash = await walletClient.writeContract({
		address: proxyAdmin,
		abi: proxyAdminAbi,
		functionName: "upgradeAndCall",
		account: viemAccount,
		args: [conceroProxy, implementation, "0x"],
		chain: viemChain,
		gas: 100000n,
	});

	log(
		`Upgraded via ${proxyAdminAlias}: ${conceroProxyAlias}.implementation -> ${implementationAlias}, hash: ${txHash}`,
		`setProxyImplementation : ${proxyType}`,
		name,
	);
}
