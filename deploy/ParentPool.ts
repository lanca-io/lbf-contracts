import { getNetworkEnvKey } from "@concero/contract-utils";
import { Deployment } from "hardhat-deploy/types";
import { HardhatRuntimeEnvironment } from "hardhat/types";
import { formatUnits, parseUnits } from "viem";

import { conceroNetworks } from "../constants";
import { getEnvVar, log, updateEnvVariable } from "../utils";

type DeployArgs = {
	liquidityToken: string;
	liquidityTokenDecimals: number;
	lpToken: string;
	conceroRouter: string;
	chainSelector: number;
	iouToken: string;
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
	const conceroRouter = getEnvVar(`CONCERO_ROUTER_PROXY_${getNetworkEnvKey(name)}`); // TODO: v2-contracts
	const iouToken = getEnvVar(`IOU_${getNetworkEnvKey(name)}`);
	const defaultLiquidityTokenDecimals = 6;
	const defaultMinTargetBalance = parseUnits("10000", defaultLiquidityTokenDecimals);

	if (!liquidityToken || !lpToken || !conceroRouter || !iouToken) {
		throw new Error("Missing env variables");
	}

	const args: DeployArgs = {
		liquidityToken,
		liquidityTokenDecimals:
			overrideArgs?.liquidityTokenDecimals || defaultLiquidityTokenDecimals,
		lpToken,
		conceroRouter,
		chainSelector: chain.chainSelector,
		iouToken,
		minTargetBalance: overrideArgs?.minTargetBalance || defaultMinTargetBalance,
	};

	const deployment = await deploy("ParentPool", {
		from: deployer,
		args: [
			args.liquidityToken,
			args.liquidityTokenDecimals,
			args.lpToken,
			args.conceroRouter,
			args.chainSelector,
			args.iouToken,
			args.minTargetBalance,
		],
		log: true,
		autoMine: true,
		skipIfAlreadyDeployed: true,
	});

	log(`ParentPool deployed at: ${deployment.address}`, "deployParentPool", name);
	log(
		`Args: 
			liquidityToken: ${args.liquidityToken}, 
			liquidityTokenDecimals: ${args.liquidityTokenDecimals}, 
			lpToken: ${args.lpToken}, 
			conceroRouter: ${args.conceroRouter}, 
			chainSelector: ${args.chainSelector}, 
			iouToken: ${args.iouToken}, 
			minTargetBalance: ${Number(formatUnits(args.minTargetBalance, args.liquidityTokenDecimals)).toFixed(args.liquidityTokenDecimals)} `,
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
