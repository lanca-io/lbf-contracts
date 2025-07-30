import { DeployOptions, Deployment } from "hardhat-deploy/types";
import { HardhatRuntimeEnvironment } from "hardhat/types";

import { getNetworkEnvKey } from "@concero/contract-utils";

import { conceroNetworks } from "../constants";
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
	const { deploy, get, execute } = hre.deployments;
	const { name } = hre.network;

	const chain = conceroNetworks[name];
	const { type: networkType } = chain;

	const iouTokenDeployment = await get("IOUToken");

	const defaultArgs = [
		getEnvVar(`USDC_${getNetworkEnvKey(name)}`) || "",
		6, // USDC decimals
		Number(chain.chainSelector), // Convert bigint to number for uint24
		iouTokenDeployment.address,
		getEnvVar(`CONCERO_ROUTER_${getNetworkEnvKey(name)}`) || "",
	];

	const args = deployOptions?.args || defaultArgs;

	const deployment = await deploy("ChildPool", {
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

	// Update IOUToken pool role to ChildPool
	if (deployment.newlyDeployed) {
		const POOL_ROLE = hre.ethers.keccak256(hre.ethers.toUtf8Bytes("POOL_ROLE"));
		await execute(
			"IOUToken",
			{ from: deployer, log: true },
			"grantRole",
			POOL_ROLE,
			deployment.address,
		);
		log("Granted POOL_ROLE to ChildPool on IOUToken", "deployChildPool", name);
	}

	return deployment;
};

deployChildPool.tags = ["ChildPool"];
deployChildPool.dependencies = ["IOUToken"];

export default deployChildPool;
export { deployChildPool };
