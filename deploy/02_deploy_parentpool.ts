import { getNetworkEnvKey } from "@concero/contract-utils";
import { DeployOptions, Deployment } from "hardhat-deploy/types";
import { HardhatRuntimeEnvironment } from "hardhat/types";

import { conceroNetworks } from "../constants";
import { getEnvVar, log, updateEnvVariable } from "../utils";

type DeploymentFunction = (
	hre: HardhatRuntimeEnvironment,
	deployOptions?: Partial<DeployOptions>,
) => Promise<Deployment>;

const deployParentPool: DeploymentFunction = async function (
	hre: HardhatRuntimeEnvironment,
	deployOptions?: Partial<DeployOptions>,
): Promise<Deployment> {
	const { deployer } = await hre.getNamedAccounts();
	const { deploy } = hre.deployments;
	const { name } = hre.network;

	const chain = conceroNetworks[name];
	const { type: networkType } = chain;

	const lpTokenAddress = getEnvVar(`LPT_${getNetworkEnvKey(name)}`);
	const iouTokenAddress = getEnvVar(`IOU_${getNetworkEnvKey(name)}`);

	const defaultArgs = [
		getEnvVar(`USDC_${getNetworkEnvKey(name)}`) || "",
		6, // USDC decimals
		lpTokenAddress,
		getEnvVar(`CONCERO_ROUTER_${getNetworkEnvKey(name)}`) || "",
		chain.chainSelector,
		iouTokenAddress,
	];

	const args = deployOptions?.args || defaultArgs;

	const deployment = await deploy(deployOptions?.contract || "ParentPool", {
		from: deployer,
		args,
		log: true,
		autoMine: true,
		skipIfAlreadyDeployed: true,
		...deployOptions,
	});

	log(`ParentPool deployed at: ${deployment.address}`, "deployParentPool", name);
	updateEnvVariable(
		`PARENT_POOL_${getNetworkEnvKey(name)}`,
		deployment.address,
		`deployments.${networkType}`,
	);

	return deployment;
};

deployParentPool.tags = ["ParentPool"];
deployParentPool.dependencies = ["LPToken", "IOUToken"];

export default deployParentPool;
export { deployParentPool };
