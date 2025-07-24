import { Deployment } from "hardhat-deploy/types";
import { HardhatRuntimeEnvironment } from "hardhat/types";

import { getNetworkEnvKey } from "@concero/contract-utils";

import { conceroNetworks } from "../constants";
import { log, updateEnvVariable } from "../utils";

type DeployArgs = {
	defaultAdmin: string;
	minter: string;
};

type DeploymentFunction = (
	hre: HardhatRuntimeEnvironment,
	overrideArgs?: Partial<DeployArgs>,
) => Promise<Deployment>;

const deployLPToken: DeploymentFunction = async function (
	hre: HardhatRuntimeEnvironment,
	overrideArgs?: Partial<DeployArgs>,
): Promise<Deployment> {
	const { deployer } = await hre.getNamedAccounts();
	const { deploy } = hre.deployments;
	const { name } = hre.network;

	const chain = conceroNetworks[name];
	const { type: networkType } = chain;

	// For initial deployment, minter will be set to deployer
	// It will be updated later when ParentPool is deployed
	const defaultArgs: DeployArgs = {
		defaultAdmin: deployer,
		minter: deployer, // Temporary - will be updated to ParentPool address
	};

	const args: DeployArgs = {
		...defaultArgs,
		...overrideArgs,
	};

	const deployment = await deploy("LPToken", {
		from: deployer,
		args: [args.defaultAdmin, args.minter],
		log: true,
		autoMine: true,
		skipIfAlreadyDeployed: true,
	});

	log(`LPToken deployed at: ${deployment.address}`, "deployLPToken", name);
	updateEnvVariable(
		`LPTOKEN_${getNetworkEnvKey(name)}`,
		deployment.address,
		`deployments.${networkType}`,
	);

	return deployment;
};

deployLPToken.tags = ["LPToken", "ParentPoolDependencies"];

export default deployLPToken;
export { deployLPToken };
