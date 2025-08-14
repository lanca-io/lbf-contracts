import { getNetworkEnvKey } from "@concero/contract-utils";
import { Deployment } from "hardhat-deploy/types";
import { HardhatRuntimeEnvironment } from "hardhat/types";

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

	const args: DeployArgs = {
		defaultAdmin: overrideArgs?.defaultAdmin || deployer,
		minter: overrideArgs?.minter || deployer,
	};

	const deployment = await deploy("LPToken", {
		from: deployer,
		args: [args.defaultAdmin, args.minter],
		log: true,
		autoMine: true,
		skipIfAlreadyDeployed: true,
	});

	log(`LPToken deployed at: ${deployment.address}`, "deployLPToken", name);
	log(`Args: ${JSON.stringify(args)}`, "deployLPToken", name);
	updateEnvVariable(
		`LPT_${getNetworkEnvKey(name)}`,
		deployment.address,
		`deployments.${chain.type}`,
	);

	return deployment;
};

deployLPToken.tags = ["LPToken"];

export default deployLPToken;
export { deployLPToken };
