import { getNetworkEnvKey } from "@concero/contract-utils";
import { DeployOptions as HardhatDeployOptions } from "hardhat-deploy/dist/types";
import { DeployOptions, Deployment } from "hardhat-deploy/types";
import { HardhatRuntimeEnvironment } from "hardhat/types";

import { conceroNetworks } from "../constants";
import { log, updateEnvVariable } from "../utils";

type DeploymentFunction = (
	hre: HardhatRuntimeEnvironment,
	deployOptions?: Partial<DeployOptions>,
) => Promise<Deployment>;

const deployLPToken: DeploymentFunction = async function (
	hre: HardhatRuntimeEnvironment,
	deployOptions?: Partial<DeployOptions>,
): Promise<Deployment> {
	const { deployer } = await hre.getNamedAccounts();
	const { deploy } = hre.deployments;
	const { name } = hre.network;

	const chain = conceroNetworks[name];
	const { type: networkType } = chain;

	const args = deployOptions?.args || [deployer, deployer];

	const deployment = await deploy(deployOptions?.contract || "LPToken", {
		from: deployer,
		args,
		log: true,
		autoMine: true,
		skipIfAlreadyDeployed: true,
		...deployOptions,
	});

	log(`LPToken deployed at: ${deployment.address}`, "deployLPToken", name);
	updateEnvVariable(
		`LPT_${getNetworkEnvKey(name)}`,
		deployment.address,
		`deployments.${networkType}`,
	);

	return deployment;
};

deployLPToken.tags = ["LPToken", "ParentPoolDependencies"];

export default deployLPToken;
export { deployLPToken };
