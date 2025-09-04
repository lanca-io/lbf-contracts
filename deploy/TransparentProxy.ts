import { hardhatDeployWrapper } from "@concero/contract-utils";
import { Deployment } from "hardhat-deploy/types";
import { HardhatRuntimeEnvironment } from "hardhat/types";

import { ProxyEnum, conceroNetworks } from "../constants";
import { DEPLOY_CONFIG_TESTNET } from "../constants/deployConfigTestnet";
import { EnvPrefixes, IProxyType } from "../types/deploymentVariables";
import { getEnvAddress, getFallbackClients, getViemAccount, log, updateEnvAddress } from "../utils";

export async function deployTransparentProxy(
	hre: HardhatRuntimeEnvironment,
	proxyType: IProxyType,
): Promise<Deployment> {
	const { name } = hre.network;

	const chain = conceroNetworks[name as keyof typeof conceroNetworks];
	const { type: networkType } = chain;

	let implementationKey: keyof EnvPrefixes;
	if (proxyType === ProxyEnum.parentPoolProxy) {
		implementationKey = "parentPool";
	} else if (proxyType === ProxyEnum.childPoolProxy) {
		implementationKey = "childPool";
	} else {
		throw new Error(`Proxy type ${proxyType} not found`);
	}

	const viemAccount = getViemAccount(chain.type, "proxyDeployer");
	const { publicClient } = getFallbackClients(chain, viemAccount);

	const [initialImplementation, initialImplementationAlias] = getEnvAddress(
		implementationKey,
		name,
	);
	const [proxyAdmin, proxyAdminAlias] = getEnvAddress(`${proxyType}Admin`, name);

	let gasLimit = 0;
	const config = DEPLOY_CONFIG_TESTNET[name];
	if (config) {
		gasLimit = config.proxy?.gasLimit || 0;
	}

	const deployment = await hardhatDeployWrapper("TransparentUpgradeableProxy", {
		hre,
		args: [initialImplementation, proxyAdmin, "0x"],
		publicClient,
		gasLimit,
		proxy: true,
	});

	log(
		`Deployed at: ${deployment.address}. Initial impl: ${initialImplementationAlias}, Proxy admin: ${proxyAdminAlias}`,
		`deployTransparentProxy: ${proxyType}`,
		name,
	);

	updateEnvAddress(proxyType, name, deployment.address, `deployments.${networkType}`);

	return deployment;
}

deployTransparentProxy.tags = ["TransparentProxy"];

export default deployTransparentProxy;
