import { getNetworkEnvKey } from "@concero/contract-utils";
import { DeployOptions, Deployment } from "hardhat-deploy/types";
import { HardhatRuntimeEnvironment } from "hardhat/types";

import { conceroNetworks } from "../constants";
import { parentPoolChainSelector } from "../constants/deploymentVariables";
import { getEnvVar, log, updateEnvVariable } from "../utils";

type DeploymentFunction = (
	hre: HardhatRuntimeEnvironment,
	deployOptions?: Partial<DeployOptions>,
) => Promise<Deployment>;

const deployChildPool: DeploymentFunction = async function (
	hre: HardhatRuntimeEnvironment,
	deployOptions?: Partial<DeployOptions>,
): Promise<Deployment> {
	const { deployer } = await hre.getNamedAccounts();
	const { deploy } = hre.deployments;
	const { name } = hre.network;

	const chain = conceroNetworks[name];
	const { type: networkType } = chain;

	const iouTokenAddress = getEnvVar(`IOU_${getNetworkEnvKey(name)}`);

	const defaultArgs = [
		getEnvVar(`CONCERO_ROUTER_${getNetworkEnvKey(name)}`) || "",
		iouTokenAddress,
		getEnvVar(`USDC_${getNetworkEnvKey(name)}`) || "",
		6, // USDC decimals
		Number(chain.chainSelector), // Convert bigint to number for uint24
		parentPoolChainSelector,
	];

	const args = deployOptions?.args || defaultArgs;

	const deployment = await deploy(deployOptions?.contract || "ChildPool", {
		from: deployer,
		args,
		log: true,
		autoMine: true,
		skipIfAlreadyDeployed: true,
		...deployOptions,
	});

	log(`ChildPool deployed at: ${deployment.address}`, "deployChildPool", name);
	updateEnvVariable(
		`CHILD_POOL_${getNetworkEnvKey(name)}`,
		deployment.address,
		`deployments.${networkType}`,
	);

	return deployment;
};

deployChildPool.tags = ["ChildPool"];
deployChildPool.dependencies = ["IOUToken"];

export default deployChildPool;
export { deployChildPool };
