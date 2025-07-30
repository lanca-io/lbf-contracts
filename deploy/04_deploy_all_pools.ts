import { DeployOptions, Deployment } from "hardhat-deploy/types";
import { HardhatRuntimeEnvironment } from "hardhat/types";

import { conceroNetworks } from "../constants";
import { log } from "../utils";
import { deployWithTransparentProxy } from "./utils/deployWithTransparentProxy";

interface DeployAllArgs {
	lpTokenDeployOptions?: Partial<DeployOptions>;
	iouTokenDeployOptions?: Partial<DeployOptions>;
	parentPoolDeployOptions?: Partial<DeployOptions>;
	childPoolDeployOptions?: Partial<DeployOptions>;
	useTransparentProxy?: boolean;
	proxyAdmin?: string;
}

interface DeploymentResult {
	lpToken: Deployment;
	iouToken: Deployment;
	parentPool: Deployment;
	childPool?: Deployment;
}

type DeploymentFunction = (
	hre: HardhatRuntimeEnvironment,
	overrideArgs?: DeployAllArgs,
) => Promise<DeploymentResult>;

const CONTRACT_TAGS = {
	LP_TOKEN: "LPToken",
	IOU_TOKEN: "IOUToken",
	PARENT_POOL: "ParentPool",
	CHILD_POOL: "ChildPool",
} as const;

const deployContractWithProxy = async (
	hre: HardhatRuntimeEnvironment,
	contractName: string,
	deployOptions?: Partial<DeployOptions>,
	useProxy = false,
	proxyAdmin?: string,
): Promise<Deployment> => {
	const { name: networkName } = hre.network;

	log(`Deploying ${contractName}...`, "deployAllPools", networkName);

	if (useProxy) {
		const result = await deployWithTransparentProxy(
			hre,
			contractName,
			deployOptions,
			proxyAdmin,
		);
		return result.proxy;
	} else {
		// Use existing deployment scripts for direct deployment
		await hre.run("deploy", {
			tags: contractName,
			...deployOptions,
		});
		return await hre.deployments.get(contractName);
	}
};

const logDeploymentResults = (result: DeploymentResult, networkName: string): void => {
	log("All pool contracts deployed successfully!", "deployAllPools", networkName);
	log(`LPToken: ${result.lpToken.address}`, "deployAllPools", networkName);
	log(`IOUToken: ${result.iouToken.address}`, "deployAllPools", networkName);
	log(`ParentPool: ${result.parentPool.address}`, "deployAllPools", networkName);

	if (result.childPool) {
		log(`ChildPool: ${result.childPool.address}`, "deployAllPools", networkName);
	}
};

const deployAllPools: DeploymentFunction = async (
	hre: HardhatRuntimeEnvironment,
	{
		lpTokenDeployOptions = {},
		iouTokenDeployOptions = {},
		parentPoolDeployOptions = {},
		childPoolDeployOptions = {},
		useTransparentProxy = false,
		proxyAdmin,
	}: DeployAllArgs = {},
): Promise<DeploymentResult> => {
	const { name: networkName } = hre.network;
	const chain = conceroNetworks[networkName];

	log("Starting deployment of all pool contracts...", "deployAllPools", networkName);

	try {
		// LPToken deployment
		const lpToken = await deployContractWithProxy(
			hre,
			CONTRACT_TAGS.LP_TOKEN,
			lpTokenDeployOptions,
			useTransparentProxy,
			proxyAdmin,
		);

		// IOUToken deployment
		const iouToken = await deployContractWithProxy(
			hre,
			CONTRACT_TAGS.IOU_TOKEN,
			iouTokenDeployOptions,
			useTransparentProxy,
			proxyAdmin,
		);

		// ParentPool deployment
		const parentPool = await deployContractWithProxy(
			hre,
			CONTRACT_TAGS.PARENT_POOL,
			parentPoolDeployOptions,
			useTransparentProxy,
			proxyAdmin,
		);

		// ChildPool deployment
		const childPool = await deployContractWithProxy(
			hre,
			CONTRACT_TAGS.CHILD_POOL,
			childPoolDeployOptions,
			useTransparentProxy,
			proxyAdmin,
		);

		const result: DeploymentResult = {
			lpToken,
			iouToken,
			parentPool,
			childPool,
		};

		logDeploymentResults(result, networkName);
		return result;
	} catch (error) {
		log(`Deployment failed: ${error}`, "deployAllPools", networkName);
		throw error;
	}
};

deployAllPools.tags = ["AllPools"];
deployAllPools.dependencies = [
	CONTRACT_TAGS.LP_TOKEN,
	CONTRACT_TAGS.IOU_TOKEN,
	CONTRACT_TAGS.PARENT_POOL,
	CONTRACT_TAGS.CHILD_POOL,
];

export default deployAllPools;
export { deployAllPools };
export type { DeployAllArgs, DeploymentResult };
