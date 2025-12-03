import { getNetworkEnvKey } from "@concero/contract-utils";
import { Deployment } from "hardhat-deploy/types";
import { HardhatRuntimeEnvironment } from "hardhat/types";
import { formatUnits, parseUnits } from "viem";

import { conceroNetworks, liqTokenDecimals } from "../constants";
import { getEnvVar, log, updateEnvVariable } from "../utils";

type DeployArgs = {
	liquidityToken: string;
	lpToken: string;
	iouToken: string;
	conceroRouter: string;
	chainSelector: number;
	minTargetBalance: bigint;
};

type DeploymentFunction = (
	hre: HardhatRuntimeEnvironment,
	overrideArgs?: Partial<DeployArgs>,
) => Promise<Deployment>;

const deployParentPool: DeploymentFunction = async function (
	hre: HardhatRuntimeEnvironment,
	overrideArgs?: Partial<DeployArgs>,
): Promise<Deployment> {
	const { deployer } = await hre.getNamedAccounts();
	const { deploy } = hre.deployments;
	const { name } = hre.network;

	const chain = conceroNetworks[name];

	const liquidityToken = getEnvVar(`USDC_PROXY_${getNetworkEnvKey(name)}`);
	const lpToken = getEnvVar(`LPT_${getNetworkEnvKey(name)}`);
	const conceroRouter = getEnvVar(`CONCERO_ROUTER_PROXY_${getNetworkEnvKey(name)}`);
	const iouToken = getEnvVar(`IOU_${getNetworkEnvKey(name)}`);
	const defaultLiquidityTokenDecimals = 6;
	const defaultMinTargetBalance = parseUnits("10000", defaultLiquidityTokenDecimals);

	if (!liquidityToken || !lpToken || !conceroRouter || !iouToken) {
		throw new Error("Missing env variables");
	}

	const args: DeployArgs = {
		liquidityToken,
		lpToken,
		iouToken,
		conceroRouter,
		chainSelector: chain.chainSelector,
		minTargetBalance: overrideArgs?.minTargetBalance || defaultMinTargetBalance,
	};

	const parentPoolLib = await deploy("ParentPoolLib", {
		from: deployer,
		args: [],
		log: true,
		autoMine: true,
		skipIfAlreadyDeployed: true,
	});

	const deployment = await deploy("ParentPool", {
		from: deployer,
		args: [
			args.liquidityToken,
			args.lpToken,
			args.iouToken,
			args.conceroRouter,
			args.chainSelector,
			args.minTargetBalance,
		],
		log: true,
		autoMine: true,
		skipIfAlreadyDeployed: true,
		libraries: {
			ParentPoolLib: parentPoolLib.address,
		},
	});

	log(`ParentPool deployed at: ${deployment.address}`, "deployParentPool", name);
	log(
		`Args: 
			liquidityToken: ${args.liquidityToken}, 
			lpToken: ${args.lpToken}, 
			iouToken: ${args.iouToken}, 
			conceroRouter: ${args.conceroRouter}, 
			chainSelector: ${args.chainSelector}, 
			minTargetBalance: ${Number(formatUnits(args.minTargetBalance, liqTokenDecimals)).toFixed(liqTokenDecimals)} 
			parentPoolLib: ${parentPoolLib.address}`,
		"deployParentPool",
		name,
	);
	updateEnvVariable(
		`PARENT_POOL_${getNetworkEnvKey(name)}`,
		deployment.address,
		`deployments.${chain.type}`,
	);

	return deployment;
};

deployParentPool.tags = ["ParentPool"];

export default deployParentPool;
export { deployParentPool };
