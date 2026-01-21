import { HardhatRuntimeEnvironment } from "hardhat/types";
import { parseUnits } from "viem";

import { conceroNetworks, defaultLiquidityTokenGasOverhead } from "../constants";
import { EnvFileName } from "../types/deploymentVariables";
import {
	IDeployResult,
	genericDeploy,
	getEnvVar,
	getNetworkEnvKey,
	updateEnvVariable,
} from "../utils";

type DeployArgs = {
	liquidityToken: string;
	lpToken: string;
	iouToken: string;
	conceroRouter: string;
	chainSelector: number;
	minTargetBalance: bigint;
	liquidityTokenGasOverhead: number;
};

type DeploymentFunction = (
	hre: HardhatRuntimeEnvironment,
	overrideArgs?: Partial<DeployArgs>,
) => Promise<IDeployResult>;

export const deployParentPool: DeploymentFunction = async (
	hre: HardhatRuntimeEnvironment,
	overrideArgs?: Partial<DeployArgs>,
): Promise<IDeployResult> => {
	const { name } = hre.network;
	const chain = conceroNetworks[name as keyof typeof conceroNetworks];

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
		chainSelector: Number(chain.chainSelector),
		minTargetBalance: overrideArgs?.minTargetBalance || defaultMinTargetBalance,
		liquidityTokenGasOverhead:
			overrideArgs?.liquidityTokenGasOverhead || defaultLiquidityTokenGasOverhead,
	};

	const parentPoolLib = await genericDeploy({
		hre,
		contractName: "ParentPoolLib",
	});

	const deployment = await genericDeploy(
		{
			hre,
			contractName: "ParentPool",
			txParams: {
				libraries: {
					ParentPoolLib: parentPoolLib.address,
				},
			},
		},
		args.liquidityToken,
		args.lpToken,
		args.iouToken,
		args.conceroRouter,
		args.chainSelector,
		args.minTargetBalance,
		args.liquidityTokenGasOverhead,
	);

	updateEnvVariable(
		`PARENT_POOL_${getNetworkEnvKey(deployment.chainName)}`,
		deployment.address,
		`deployments.${deployment.chainType}` as EnvFileName,
	);

	return deployment;
};
