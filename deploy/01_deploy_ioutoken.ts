import { Deployment } from "hardhat-deploy/types";
import { HardhatRuntimeEnvironment } from "hardhat/types";

import { getNetworkEnvKey } from "@concero/contract-utils";

import { conceroNetworks } from "../constants";
import { log, updateEnvVariable } from "../utils";

type DeployArgs = {
	admin: string;
	pool: string;
};

type DeploymentFunction = (
	hre: HardhatRuntimeEnvironment,
	overrideArgs?: Partial<DeployArgs>,
) => Promise<Deployment>;

const deployIOUToken: DeploymentFunction = async function (
	hre: HardhatRuntimeEnvironment,
	overrideArgs?: Partial<DeployArgs>,
): Promise<Deployment> {
	const { deployer } = await hre.getNamedAccounts();
	const { deploy } = hre.deployments;
	const { name } = hre.network;

	const chain = conceroNetworks[name];
	const { type: networkType } = chain;

	// For initial deployment, pool will be set to deployer
	// It will be updated later when pools are deployed
	const defaultArgs: DeployArgs = {
		admin: deployer,
		pool: deployer, // Temporary - will be updated to pool addresses
	};

	const args: DeployArgs = {
		...defaultArgs,
		...overrideArgs,
	};

	const deployment = await deploy("IOUToken", {
		from: deployer,
		args: [args.admin, args.pool],
		log: true,
		autoMine: true,
		skipIfAlreadyDeployed: true,
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
