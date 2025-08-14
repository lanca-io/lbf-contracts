import { Deployment } from "hardhat-deploy/types";
import { HardhatRuntimeEnvironment } from "hardhat/types";

import { ProxyEnum, conceroNetworks } from "../constants";
import { EnvPrefixes, IProxyType } from "../types/deploymentVariables";
import { getEnvAddress, log, updateEnvAddress } from "../utils";

export async function deployTransparentProxy(
	hre: HardhatRuntimeEnvironment,
	proxyType: IProxyType,
): Promise<Deployment> {
	const { proxyDeployer } = await hre.getNamedAccounts();
	const { deploy } = hre.deployments;
	const { name } = hre.network;

	const chain = conceroNetworks[name];
	const { type: networkType } = chain;

	let implementationKey: keyof EnvPrefixes;
	if (proxyType === ProxyEnum.parentPoolProxy) {
		implementationKey = "parentPool";
	} else if (proxyType === ProxyEnum.childPoolProxy) {
		implementationKey = "childPool";
	} else {
		throw new Error(`Proxy type ${proxyType} not found`);
	}

	const [initialImplementation, initialImplementationAlias] = getEnvAddress(
		implementationKey,
		name,
	);
	const [proxyAdmin, proxyAdminAlias] = getEnvAddress(`${proxyType}Admin`, name);

	log("Deploying...", `deployTransparentProxy:${proxyType}`, name);
	const deployment = await deploy("TransparentUpgradeableProxy", {
		from: proxyDeployer,
		args: [initialImplementation, proxyAdmin, "0x"],
		log: true,
		skipIfAlreadyDeployed: true,
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
