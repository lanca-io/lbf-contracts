import { DeployOptions, Deployment } from "hardhat-deploy/types";
import { HardhatRuntimeEnvironment } from "hardhat/types";

import { getNetworkEnvKey } from "@concero/contract-utils";

import { conceroNetworks } from "../constants";
import { log, updateEnvVariable } from "../utils";

type DeploymentFunction = (
	hre: HardhatRuntimeEnvironment,
	deployOptions?: Partial<DeployOptions>,
) => Promise<Deployment>;

const deployIOUToken: DeploymentFunction = async function (
	hre: HardhatRuntimeEnvironment,
	deployOptions?: Partial<DeployOptions>,
): Promise<Deployment> {
	const { deployer } = await hre.getNamedAccounts();
	const { deploy } = hre.deployments;
	const { name } = hre.network;

	const chain = conceroNetworks[name];
	const { type: networkType } = chain;

	const args = deployOptions?.args || [deployer, deployer];

	const deployment = await deploy("IOUToken", {
		from: deployer,
		args,
		log: true,
		autoMine: true,
		skipIfAlreadyDeployed: true,
		...deployOptions,
	});

	log(`IOUToken deployed at: ${deployment.address}`, "deployIOUToken", name);
	updateEnvVariable(
		`IOUTOKEN_${getNetworkEnvKey(name)}`,
		deployment.address,
		`deployments.${networkType}`,
	);

	return deployment;
};

deployIOUToken.tags = ["IOUToken", "ParentPoolDependencies", "ChildPoolDependencies"];

export default deployIOUToken;
export { deployIOUToken };
