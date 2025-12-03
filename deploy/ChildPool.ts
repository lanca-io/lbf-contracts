import { getNetworkEnvKey, hardhatDeployWrapper } from "@concero/contract-utils";
import { Deployment } from "hardhat-deploy/types";
import { HardhatRuntimeEnvironment } from "hardhat/types";

import { conceroNetworks } from "../constants";
import { DEPLOY_CONFIG_TESTNET } from "../constants/deployConfigTestnet";
import { parentPoolChainSelectors } from "../constants/deploymentVariables";
import { getEnvVar, getFallbackClients, getViemAccount, log, updateEnvVariable } from "../utils";

type DeployArgs = {
	conceroRouter: string;
	iouToken: string;
	liquidityToken: string;
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
	const { name } = hre.network;

	const chain = conceroNetworks[name as keyof typeof conceroNetworks];

	const conceroRouter = getEnvVar(`CONCERO_ROUTER_PROXY_${getNetworkEnvKey(name)}`);
	const iouToken = getEnvVar(`IOU_${getNetworkEnvKey(name)}`);
	const liquidityToken = getEnvVar(`USDC_PROXY_${getNetworkEnvKey(name)}`);

	if (!conceroRouter || !iouToken || !liquidityToken) {
		throw new Error("Missing env variables for ChildPool deployment");
	}

	const viemAccount = getViemAccount(chain.type, "deployer");
	const { publicClient } = getFallbackClients(chain, viemAccount);

	const args: DeployArgs = {
		conceroRouter,
		iouToken,
		liquidityToken,
		chainSelector: Number(chain.chainSelector),
		parentPoolChainSelector: parentPoolChainSelectors[chain.type],
	};

	let gasLimit = 0;
	const config = DEPLOY_CONFIG_TESTNET[name];
	if (config) {
		gasLimit = config.childPool?.gasLimit || 0;
	}

	const deployment = await hardhatDeployWrapper("ChildPool", {
		hre,
		args: [
			args.conceroRouter,
			args.iouToken,
			args.liquidityToken,
			args.chainSelector,
			args.parentPoolChainSelector,
		],
		publicClient,
		gasLimit,
		skipIfAlreadyDeployed: true,
	});

	log(`ChildPool deployed at: ${deployment.address}`, "deployChildPool", name);
	log(
		`Args: 
			conceroRouter: ${args.conceroRouter}, 
			iouToken: ${args.iouToken}, 
			liquidityToken: ${args.liquidityToken}, 
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
