import { HardhatRuntimeEnvironment } from "hardhat/types";

import { ProxyEnum, conceroNetworks, getViemReceiptConfig } from "../../constants";
import { EnvPrefixes, IProxyType } from "../../types/deploymentVariables";
import { err, getEnvAddress, getFallbackClients, log } from "../../utils";
import { getViemAccount } from "../../utils/getViemClients";

export async function upgradeProxyImplementation(
	hre: HardhatRuntimeEnvironment,
	proxyType: IProxyType,
	shouldPause: boolean,
) {
	const { name } = hre.network;
	const { viemChain, type } = conceroNetworks[name];

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

	const { abi: proxyAdminAbi } = await import(
		"../../artifacts/contracts/Proxy/LancaProxyAdmin.sol/LancaProxyAdmin.json"
	);

	const viemAccount = getViemAccount(type, "proxyDeployer");
	const { walletClient, publicClient } = getFallbackClients(conceroNetworks[name], viemAccount);

	const [conceroProxy, conceroProxyAlias] = getEnvAddress(proxyType, name);
	const [proxyAdmin, proxyAdminAlias] = getEnvAddress(`${proxyType}Admin`, name);
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
		gas: 100000,
	});

	log(
		`Upgraded via ${proxyAdminAlias}: ${conceroProxyAlias}.implementation -> ${implementationAlias}, hash: ${txHash}`,
		`setProxyImplementation : ${proxyType}`,
		name,
	);
}
