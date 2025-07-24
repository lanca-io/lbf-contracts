import { Deployment } from "hardhat-deploy/types";
import { HardhatRuntimeEnvironment } from "hardhat/types";

import { conceroNetworks } from "../constants";
import { log } from "../utils";

interface TokenArgs {
	defaultAdmin?: string;
	minter?: string;
}

interface IOUTokenArgs {
	admin?: string;
	pool?: string;
}

interface PoolArgs {
	liquidityToken?: string;
	liquidityTokenDecimals?: number;
	conceroRouter?: string;
}

interface DeployAllArgs {
	lpTokenArgs?: TokenArgs;
	iouTokenArgs?: IOUTokenArgs;
	parentPoolArgs?: PoolArgs;
	childPoolArgs?: PoolArgs;
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

const deployContract = async (
	hre: HardhatRuntimeEnvironment,
	contractTag: string,
	overrideArgs: Record<string, any> = {},
): Promise<Deployment> => {
	const { name: networkName, run } = hre;

	log(`Deploying ${contractTag}...`, "deployAllPools", networkName);

	await run("deploy", {
		tags: contractTag,
		...overrideArgs,
	});

	return await hre.deployments.get(contractTag);
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
	overrideArgs: DeployAllArgs = {},
): Promise<DeploymentResult> => {
	const { name: networkName } = hre.network;
	const chain = conceroNetworks[networkName];

	log("Starting deployment of all pool contracts...", "deployAllPools", networkName);

	try {
		const lpToken = await deployContract(hre, CONTRACT_TAGS.LP_TOKEN, overrideArgs.lpTokenArgs);

		const iouToken = await deployContract(
			hre,
			CONTRACT_TAGS.IOU_TOKEN,
			overrideArgs.iouTokenArgs,
		);

		const parentPool = await deployContract(
			hre,
			CONTRACT_TAGS.PARENT_POOL,
			overrideArgs.parentPoolArgs,
		);

		let childPool: Deployment = await deployContract(
			hre,
			CONTRACT_TAGS.CHILD_POOL,
			overrideArgs.childPoolArgs,
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
