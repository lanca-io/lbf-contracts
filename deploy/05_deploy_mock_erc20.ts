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

const deployMockERC20: DeploymentFunction = async function (
	hre: HardhatRuntimeEnvironment,
	deployOptions?: Partial<DeployOptions>,
): Promise<Deployment> {
	const { deployer } = await hre.getNamedAccounts();
	const { deploy } = hre.deployments;
	const { name } = hre.network;

	const chain = conceroNetworks[name];
	const { type: networkType } = chain;

	const nameArg = deployOptions?.args?.[0] || "USD Coin";
	const symbolArg = deployOptions?.args?.[1] || "USDC";
	const decimalsArg = deployOptions?.args?.[2] || 6;

	const args = [nameArg, symbolArg, decimalsArg];

	const deployment = await deploy("MockERC20", {
		from: deployer,
		contract: "MockERC20",
		args,
		log: true,
		autoMine: true,
		skipIfAlreadyDeployed: true,
		...deployOptions,
	});

	log(`MockERC20 (${nameArg}) deployed at: ${deployment.address}`, "deployMockERC20", name);
	updateEnvVariable(
		`${symbolArg}_${getNetworkEnvKey(name)}`,
		deployment.address,
		`deployments.${networkType}`,
	);

	return deployment;
};

deployMockERC20.tags = ["MockERC20"];

export default deployMockERC20;
export { deployMockERC20 };
