import { Deployment } from "hardhat-deploy/types";
import { HardhatRuntimeEnvironment } from "hardhat/types";

import { conceroNetworks } from "../constants";
import { log } from "../utils";

type DeployAllArgs = {
	lpTokenArgs?: {
		defaultAdmin?: string;
		minter?: string;
	};
	iouTokenArgs?: {
		admin?: string;
		pool?: string;
	};
	parentPoolArgs?: {
		liquidityToken?: string;
		liquidityTokenDecimals?: number;
		conceroRouter?: string;
	};
	childPoolArgs?: {
		liquidityToken?: string;
		liquidityTokenDecimals?: number;
		conceroRouter?: string;
	};
};

type DeploymentResult = {
	lpToken: Deployment;
	iouToken: Deployment;
	parentPool: Deployment;
	childPool?: Deployment;
};

type DeploymentFunction = (
	hre: HardhatRuntimeEnvironment,
	overrideArgs?: DeployAllArgs,
) => Promise<DeploymentResult>;

const deployAllPools: DeploymentFunction = async function (
	hre: HardhatRuntimeEnvironment,
	overrideArgs?: DeployAllArgs,
): Promise<DeploymentResult> {
	const { name } = hre.network;
	const { run } = hre;

	const chain = conceroNetworks[name];
	const { type: networkType } = chain;

	log("Starting deployment of all pool contracts...", "deployAllPools", name);

	// Deploy LPToken
	log("Deploying LPToken...", "deployAllPools", name);
	await run("deploy", {
		tags: "LPToken",
		...(overrideArgs?.lpTokenArgs || {}),
	});
	const lpToken = await hre.deployments.get("LPToken");

	// Deploy IOUToken
	log("Deploying IOUToken...", "deployAllPools", name);
	await run("deploy", {
		tags: "IOUToken",
		...(overrideArgs?.iouTokenArgs || {}),
	});
	const iouToken = await hre.deployments.get("IOUToken");

	// Deploy ParentPool
	log("Deploying ParentPool...", "deployAllPools", name);
	await run("deploy", {
		tags: "ParentPool",
		...(overrideArgs?.parentPoolArgs || {}),
	});
	const parentPool = await hre.deployments.get("ParentPool");

	// Deploy ChildPool (optional - might not be needed on all networks)
	let childPool: Deployment | undefined;
	const shouldDeployChildPool = networkType === "testnet" || networkType === "localhost";

	if (shouldDeployChildPool) {
		log("Deploying ChildPool...", "deployAllPools", name);
		await run("deploy", {
			tags: "ChildPool",
			...(overrideArgs?.childPoolArgs || {}),
		});
		childPool = await hre.deployments.get("ChildPool");
	} else {
		log("Skipping ChildPool deployment on mainnet", "deployAllPools", name);
	}

	log("All pool contracts deployed successfully!", "deployAllPools", name);
	log(`LPToken: ${lpToken.address}`, "deployAllPools", name);
	log(`IOUToken: ${iouToken.address}`, "deployAllPools", name);
	log(`ParentPool: ${parentPool.address}`, "deployAllPools", name);
	if (childPool) {
		log(`ChildPool: ${childPool.address}`, "deployAllPools", name);
	}

	return {
		lpToken,
		iouToken,
		parentPool,
		childPool,
	};
};

deployAllPools.tags = ["AllPools"];
deployAllPools.dependencies = ["LPToken", "IOUToken", "ParentPool", "ChildPool"];

export default deployAllPools;
export { deployAllPools };
