import { Deployment } from "hardhat-deploy/types";
import { HardhatRuntimeEnvironment } from "hardhat/types";

import { conceroNetworks } from "../constants";
import { IProxyType } from "../types/deploymentVariables";
import { getWallet, log, updateEnvAddress } from "../utils";

export async function deployProxyAdmin(
	hre: HardhatRuntimeEnvironment,
	proxyType: IProxyType,
): Promise<Deployment> {
	const { proxyDeployer } = await hre.getNamedAccounts();
	const { deploy } = hre.deployments;
	const { name } = hre.network;

	const chain = conceroNetworks[name as keyof typeof conceroNetworks];
	const { type: networkType } = chain;

	const initialOwner = getWallet(networkType, "proxyDeployer", "address");

	const deployment = await deploy("LancaProxyAdmin", {
		from: proxyDeployer,
		args: [initialOwner],
		log: true,
		autoMine: true,
		skipIfAlreadyDeployed: false,
	});

	log(
		`Deployed at: ${deployment.address}. initialOwner: ${initialOwner}`,
		`deployProxyAdmin: ${proxyType}`,
		name,
	);
	updateEnvAddress(`${proxyType}Admin`, name, deployment.address, `deployments.${networkType}`);

	return deployment;
}

deployProxyAdmin.tags = ["LancaProxyAdmin"];

export default deployProxyAdmin;
