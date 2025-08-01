import { getNetworkEnvKey } from "@concero/contract-utils";
import { Deployment } from "hardhat-deploy/types";
import { HardhatRuntimeEnvironment } from "hardhat/types";

import { conceroNetworks } from "../../constants";
import { updateEnvVariable } from "../../utils";
import { deployProxyAdmin } from "./deployProxyAdmin";
import { deployTransparentProxy } from "./deployTransparentProxy";

export async function deployWithTransparentProxy(
	hre: HardhatRuntimeEnvironment,
	contractName: string,
	deployOptions?: any,
	proxyAdminAddress?: string,
): Promise<{ implementation: Deployment; proxy: Deployment; proxyAdmin: Deployment }> {
	const { deployer } = await hre.getNamedAccounts();
	const { deploy } = hre.deployments;
	const { name } = hre.network;

	const chain = conceroNetworks[name];
	const { type: networkType } = chain;

	const implementation = await deploy(contractName, {
		contract: contractName,
		from: deployer,
		...deployOptions,
	});

	updateEnvVariable(
		`${contractName}_IMPLEMENTATION_${getNetworkEnvKey(name)}`,
		implementation.address,
		`deployments.${networkType}`,
	);

	// Deploy unique proxy admin for this specific contract
	let proxyAdmin: Deployment;
	if (proxyAdminAddress) {
		// Use provided proxy admin address (assumes it's already deployed)
		proxyAdmin = {
			address: proxyAdminAddress,
			abi: [], // This would need to be fetched properly in real usage
		} as Deployment;
	} else {
		proxyAdmin = await deployProxyAdmin(hre, contractName, deployOptions);
	}

	// Deploy proxy
	const proxyName = `${contractName}`;
	const proxy = await deployTransparentProxy(
		hre,
		proxyName,
		implementation.address,
		proxyAdmin.address,
		deployOptions,
	);

	return {
		implementation,
		proxy,
		proxyAdmin,
	};
}
