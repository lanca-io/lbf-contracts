import { getNetworkEnvKey } from "@concero/contract-utils";
import { Deployment } from "hardhat-deploy/types";
import { HardhatRuntimeEnvironment } from "hardhat/types";

import { conceroNetworks } from "../constants";
import { parentPoolChainSelectors } from "../constants/deploymentVariables";
import { getEnvVar, log, updateEnvVariable } from "../utils";

type DeployArgs = {
	conceroRouter: string;
	iouToken: string;
	liquidityToken: string;
	liquidityTokenDecimals: number;
	chainSelector: number;
	parentPoolChainSelector: number;
};

type DeploymentFunction = (
	hre: HardhatRuntimeEnvironment,
	overrideArgs?: Partial<DeployArgs>,
) => Promise<Deployment>;

const deployChildPool: DeploymentFunction = async function (
	hre: HardhatRuntimeEnvironment,
	overrideArgs?: Partial<DeployArgs>,
): Promise<Deployment> {
	const { deployer } = await hre.getNamedAccounts();
	const { deploy } = hre.deployments;
	const { name } = hre.network;

	const chain = conceroNetworks[name as keyof typeof conceroNetworks];

	const conceroRouter = getEnvVar(`CONCERO_ROUTER_${getNetworkEnvKey(name)}`);
	const iouToken = getEnvVar(`IOU_${getNetworkEnvKey(name)}`);
	const liquidityToken = getEnvVar(`USDC_${getNetworkEnvKey(name)}`);
	const defaultLiquidityTokenDecimals = 6;

	if (!conceroRouter || !iouToken || !liquidityToken) {
		throw new Error("Missing env variables for ChildPool deployment");
	}

	const args: DeployArgs = {
		conceroRouter,
		iouToken,
		liquidityToken,
		liquidityTokenDecimals:
			overrideArgs?.liquidityTokenDecimals || defaultLiquidityTokenDecimals,
		chainSelector: Number(chain.chainSelector),
		parentPoolChainSelector: parentPoolChainSelectors[chain.type],
	};

	const deployment = await deploy("ChildPool", {
		from: deployer,
		args: [
			args.conceroRouter,
			args.iouToken,
			args.liquidityToken,
			args.liquidityTokenDecimals,
			args.chainSelector,
			args.parentPoolChainSelector,
		],
		log: true,
		autoMine: true,
		skipIfAlreadyDeployed: true,
	});

	log(`ChildPool deployed at: ${deployment.address}`, "deployChildPool", name);
	log(
		`Args: 
			conceroRouter: ${args.conceroRouter}, 
			iouToken: ${args.iouToken}, 
			liquidityToken: ${args.liquidityToken}, 
			liquidityTokenDecimals: ${args.liquidityTokenDecimals}, 
			chainSelector: ${args.chainSelector}, 
			parentPoolChainSelector: ${args.parentPoolChainSelector}`,
		"deployChildPool",
		name,
	);
	updateEnvVariable(
		`CHILD_POOL_${getNetworkEnvKey(name)}`,
		deployment.address,
		`deployments.${chain.type}`,
	);

	return deployment;
};

deployChildPool.tags = ["ChildPool"];

export default deployChildPool;
export { deployChildPool };
