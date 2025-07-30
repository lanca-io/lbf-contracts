import { DeployOptions, Deployment } from "hardhat-deploy/types";
import { HardhatRuntimeEnvironment } from "hardhat/types";

import { getNetworkEnvKey } from "@concero/contract-utils";

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
	const { deploy, get, execute } = hre.deployments;
	const { name } = hre.network;

	const chain = conceroNetworks[name];
	const { type: networkType } = chain;

	const lpTokenDeployment = await get("LPToken");
	const iouTokenDeployment = await get("IOUToken");

	const defaultArgs = [
		getEnvVar(`USDC_${getNetworkEnvKey(name)}`) || "",
		6, // USDC decimals
		lpTokenDeployment.address,
		getEnvVar(`CONCERO_ROUTER_${getNetworkEnvKey(name)}`) || "",
		chain.chainSelector,
		iouTokenDeployment.address,
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

	// Update LPToken minter role to ParentPool
	if (deployment.newlyDeployed) {
		const MINTER_ROLE = hre.ethers.keccak256(hre.ethers.toUtf8Bytes("MINTER_ROLE"));
		await execute(
			"LPToken",
			{ from: deployer, log: true },
			"grantRole",
			MINTER_ROLE,
			deployment.address,
		);
		log("Granted MINTER_ROLE to ParentPool on LPToken", "deployParentPool", name);

		// Update IOUToken pool role to ParentPool
		await execute(
			"IOUToken",
			{ from: deployer, log: true },
			"grantRole",
			MINTER_ROLE,
			deployment.address,
		);
		log("Granted MINTER_ROLE to ParentPool on IOUToken", "deployParentPool", name);
	}

	return deployment;
};

deployParentPool.tags = ["ParentPool"];
deployParentPool.dependencies = ["LPToken", "IOUToken"];

export default deployParentPool;
export { deployParentPool };
