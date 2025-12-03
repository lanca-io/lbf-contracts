import { hardhatDeployWrapper } from "@concero/contract-utils";
import { Deployment } from "hardhat-deploy/types";
import { HardhatRuntimeEnvironment } from "hardhat/types";
import { encodeFunctionData } from "viem";

import { ProxyEnum, conceroNetworks } from "../constants";
import { DEPLOY_CONFIG_TESTNET } from "../constants/deployConfigTestnet";
import { lancaProxyAbi } from "../constants/lancaProxyAbi";
import { EnvPrefixes, IProxyType } from "../types/deploymentVariables";
import {
	err,
	getEnvAddress,
	getEnvVar,
	getFallbackClients,
	getViemAccount,
	log,
	updateEnvAddress,
} from "../utils";

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

	const adminAddress = viemAccount.address;
	const lancaKeeperAddress = getEnvVar(`LANCA_KEEPER`);
	if (!lancaKeeperAddress) {
		err("Missing LANCA_KEEPER address", "deployTransparentProxy", name);
		return {} as Deployment;
	}

	const poolInitializeData = encodeFunctionData({
		abi: lancaProxyAbi,
		functionName: "initialize",
		args: [adminAddress, lancaKeeperAddress],
	});

	const deployment = await hardhatDeployWrapper("TransparentUpgradeableProxy", {
		hre,
		args: [initialImplementation, proxyAdmin, poolInitializeData],
		publicClient,
		gasLimit,
		proxy: true,
	});

	log(
		`Deployed at: ${deployment.address}. 
		Initial impl: ${initialImplementationAlias}, 
		Proxy admin: ${proxyAdminAlias},
		Hash: ${deployment.transactionHash},
		Pool initialize data: ${poolInitializeData}
		`,
		`deployTransparentProxy: ${proxyType}`,
		name,
	);

	updateEnvAddress(proxyType, name, deployment.address, `deployments.${networkType}`);

	return deployment;
}

deployTransparentProxy.tags = ["TransparentProxy"];

export default deployTransparentProxy;
