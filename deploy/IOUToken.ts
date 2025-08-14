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

const deployIOUToken: DeploymentFunction = async function (
	hre: HardhatRuntimeEnvironment,
	overrideArgs?: Partial<DeployArgs>,
): Promise<Deployment> {
	const { deployer } = await hre.getNamedAccounts();
	const { deploy } = hre.deployments;
	const { name } = hre.network;

	const chain = conceroNetworks[name as keyof typeof conceroNetworks];

	const args: DeployArgs = {
		defaultAdmin: overrideArgs?.defaultAdmin || deployer,
		minter: overrideArgs?.minter || deployer,
	};

	const deployment = await deploy("IOUToken", {
		from: deployer,
		args: [args.defaultAdmin, args.minter],
		log: true,
		autoMine: true,
		skipIfAlreadyDeployed: true,
	});

	log(`IOUToken deployed at: ${deployment.address}`, "deployIOUToken", name);
	log(`Args: ${JSON.stringify(args)}`, "deployIOUToken", name);
	updateEnvVariable(
		`IOU_${getNetworkEnvKey(name)}`,
		deployment.address,
		`deployments.${chain.type}`,
	);

	return deployment;
};

deployIOUToken.tags = ["IOUToken"];

export default deployIOUToken;
export { deployIOUToken };
