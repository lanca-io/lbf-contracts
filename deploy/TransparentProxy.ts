import { hardhatDeployWrapper } from "@concero/contract-utils";
import { Deployment } from "hardhat-deploy/types";
import { HardhatRuntimeEnvironment } from "hardhat/types";
import { Hex } from "viem";

import { ADMIN_SLOT, ProxyEnum, conceroNetworks } from "../constants";
import { DEPLOY_CONFIG_TESTNET } from "../constants/deployConfigTestnet";
import { EnvFileName, EnvPrefixes, IProxyType } from "../types/deploymentVariables";
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
	callData?: Hex,
): Promise<Deployment> {
	const { name } = hre.network;
	const [deployer] = await hre.ethers.getSigners();

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

	const viemAccount = getViemAccount(chain.type, "deployer");
	const { publicClient } = getFallbackClients(chain, viemAccount);

	const [initialImplementation, initialImplementationAlias] = getEnvAddress(
		implementationKey,
		name,
	);

	let gasLimit = 0;
	const config = DEPLOY_CONFIG_TESTNET[name];
	if (config) {
		gasLimit = config.proxy?.gasLimit || 0;
	}

	const proxyDeployment = await hardhatDeployWrapper("TransparentUpgradeableProxy", {
		hre,
		args: [initialImplementation, deployer.address, callData || "0x"],
		publicClient,
		gasLimit,
		log: true,
	});

	const proxyAdminBytes = await publicClient.getStorageAt({
		address: proxyDeployment.address as Hex,
		slot: ADMIN_SLOT as Hex,
	});

	const proxyAdminAddress = `0x${proxyAdminBytes!.slice(-40)}` as Hex;

	updateEnvAddress(
		`${proxyType}Admin`,
		name,
		proxyAdminAddress,
		`deployments.${networkType}` as EnvFileName,
	);

	updateEnvAddress(
		proxyType,
		name,
		proxyDeployment.address,
		`deployments.${networkType}` as EnvFileName,
	);

	log(
		`Deployed at: ${proxyDeployment.address}.
		Initial impl: ${initialImplementationAlias},
		Proxy admin: ${proxyAdminAddress},
		Hash: ${proxyDeployment.transactionHash},
		Pool initialize data: ${callData}`,
		`deployTransparentProxy: ${proxyType}`,
		name,
	);

	return proxyDeployment;
}

deployTransparentProxy.tags = ["TransparentProxy"];

export default deployTransparentProxy;
