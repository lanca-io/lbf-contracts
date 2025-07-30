import { Deployment } from "hardhat-deploy/types";
import { HardhatRuntimeEnvironment } from "hardhat/types";

import { getNetworkEnvKey } from "@concero/contract-utils";

import { conceroNetworks } from "../../constants";
import { updateEnvVariable } from "../../utils";

export async function deployTransparentProxy(
	hre: HardhatRuntimeEnvironment,
	proxyName: string,
	implementationAddress: string,
	proxyAdminAddress: string,
	deployOptions?: any,
): Promise<Deployment> {
	const { deployer } = await hre.getNamedAccounts();
	const { deploy } = hre.deployments;
	const { name } = hre.network;

	const chain = conceroNetworks[name];
	const { type: networkType } = chain;

	const deployment = await deploy("TransparentUpgradeableProxy", {
		contract: "TransparentUpgradeableProxy",
		from: deployer,
		args: [implementationAddress, proxyAdminAddress, "0x"],
		log: true,
		skipIfAlreadyDeployed: true,
		...deployOptions,
	});

	updateEnvVariable(
		`${proxyName}_PROXY_${getNetworkEnvKey(name)}`,
		deployment.address,
		`deployments.${networkType}`,
	);

	return deployment;
}
