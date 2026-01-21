import { HardhatRuntimeEnvironment } from "hardhat/types";
import { Hex } from "viem";

import { DEPLOY_CONFIG_TESTNET, ProxyEnum } from "../constants";
import { EnvFileName, EnvPrefixes, IProxyType } from "../types/deploymentVariables";
import {
	IDeployResult,
	extractProxyAdminAddress,
	genericDeploy,
	getEnvAddress,
	log,
	updateEnvAddress,
} from "../utils";

export const deployTransparentProxy = async (
	hre: HardhatRuntimeEnvironment,
	proxyType: IProxyType,
	callData?: Hex,
): Promise<IDeployResult> => {
	const { name } = hre.network;
	const [deployer] = await hre.ethers.getSigners();

	let implementationKey: keyof EnvPrefixes;
	if (proxyType === ProxyEnum.parentPoolProxy) {
		implementationKey = "parentPool";
	} else if (proxyType === ProxyEnum.childPoolProxy) {
		implementationKey = "childPool";
	} else {
		throw new Error(`Proxy type ${proxyType} not found`);
	}

	const [initialImplementation] = getEnvAddress(implementationKey, name);

	let gasLimit = 0;
	const config = DEPLOY_CONFIG_TESTNET[name];
	if (config) {
		gasLimit = config.proxy?.gasLimit || 0;
	}

	const deployment = await genericDeploy(
		{
			hre,
			contractName: "TransparentUpgradeableProxy",
			txParams: {
				gasLimit: BigInt(gasLimit),
			},
		},
		initialImplementation,
		deployer.address,
		callData ?? "0x",
	);

	updateEnvAddress(
		proxyType,
		deployment.address,
		`deployments.${deployment.chainType}` as EnvFileName,
		deployment.chainName,
	);

	const proxyAdminAddress = extractProxyAdminAddress(deployment.receipt);

	log(
		`Deployed at: ${proxyAdminAddress}. initialOwner: ${deployer.address}`,
		`deployProxyAdmin: ${proxyType}`,
		deployment.chainName,
	);

	updateEnvAddress(
		`${proxyType}Admin`,
		proxyAdminAddress as Hex,
		`deployments.${deployment.chainType}` as EnvFileName,
		deployment.chainName,
	);

	return deployment;
};
