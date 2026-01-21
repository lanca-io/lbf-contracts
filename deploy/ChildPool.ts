import { HardhatRuntimeEnvironment } from "hardhat/types";

import { conceroNetworks } from "../constants";
import { DEPLOY_CONFIG_TESTNET } from "../constants/deployConfigTestnet";
import {
	defaultLiquidityTokenGasOverhead,
	parentPoolChainSelectors,
} from "../constants/deploymentVariables";
import { EnvFileName } from "../types/deploymentVariables";
import {
	IDeployResult,
	genericDeploy,
	getEnvVar,
	getNetworkEnvKey,
	updateEnvVariable,
} from "../utils";

type DeployArgs = {
	conceroRouter: string;
	iouToken: string;
	liquidityToken: string;
	chainSelector: number;
	parentPoolChainSelector: number;
	liquidityTokenGasOverhead: number;
};

type DeploymentFunction = (
	hre: HardhatRuntimeEnvironment,
	overrideArgs?: Partial<DeployArgs>,
) => Promise<IDeployResult>;

export const deployChildPool: DeploymentFunction = async (
	hre: HardhatRuntimeEnvironment,
	overrideArgs?: Partial<DeployArgs>,
): Promise<IDeployResult> => {
	const { name } = hre.network;
	const chain = conceroNetworks[name as keyof typeof conceroNetworks];

	const conceroRouter = getEnvVar(`CONCERO_ROUTER_PROXY_${getNetworkEnvKey(name)}`);
	const iouToken = getEnvVar(`IOU_${getNetworkEnvKey(name)}`);
	const liquidityToken = getEnvVar(`USDC_PROXY_${getNetworkEnvKey(name)}`);

	if (!conceroRouter || !iouToken || !liquidityToken) {
		throw new Error("Missing env variables for ChildPool deployment");
	}

	const args: DeployArgs = {
		conceroRouter,
		iouToken,
		liquidityToken,
		chainSelector: Number(chain.chainSelector),
		parentPoolChainSelector: parentPoolChainSelectors[chain.type],
		liquidityTokenGasOverhead:
			overrideArgs?.liquidityTokenGasOverhead || defaultLiquidityTokenGasOverhead,
	};

	let gasLimit = 0;
	const config = DEPLOY_CONFIG_TESTNET[name];
	if (config) {
		gasLimit = config.childPool?.gasLimit || 0;
	}

	const deployment = await genericDeploy(
		{
			hre,
			contractName: "ChildPool",
			txParams: {
				gasLimit: BigInt(gasLimit),
			},
		},
		args.conceroRouter,
		args.iouToken,
		args.liquidityToken,
		args.chainSelector,
		args.parentPoolChainSelector,
		args.liquidityTokenGasOverhead,
	);

	updateEnvVariable(
		`CHILD_POOL_${getNetworkEnvKey(deployment.chainName)}`,
		deployment.address,
		`deployments.${deployment.chainType}` as EnvFileName,
	);

	return deployment;
};
