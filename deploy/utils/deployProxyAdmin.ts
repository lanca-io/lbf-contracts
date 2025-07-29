import { Deployment } from "hardhat-deploy/types";
import { HardhatRuntimeEnvironment } from "hardhat/types";

import { getNetworkEnvKey } from "@concero/contract-utils";

import { conceroNetworks } from "../../constants";
import { updateEnvVariable } from "../../utils";

export async function deployProxyAdmin(
	hre: HardhatRuntimeEnvironment,
	proxyAdminName: string,
	deployOptions?: any,
): Promise<Deployment> {
	const { deployer } = await hre.getNamedAccounts();
	const { deploy } = hre.deployments;
	const { name } = hre.network;

	const chain = conceroNetworks[name];
	const { type: networkType } = chain;

	const deployment = await deploy(`LancaProxyAdmin_${proxyAdminName}`, {
		contract: "LancaProxyAdmin",
		from: deployer,
		args: [],
		log: true,
		skipIfAlreadyDeployed: true,
		...deployOptions,
	});

	updateEnvVariable(
		`${proxyAdminName}_PROXY_ADMIN_${getNetworkEnvKey(name)}`,
		deployment.address,
		`deployments.${networkType}`,
	);

	return deployment;
}
