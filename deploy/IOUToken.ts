import { HardhatRuntimeEnvironment } from "hardhat/types";

import { conceroNetworks, liqTokenDecimals } from "../constants";
import { DEPLOY_CONFIG_TESTNET } from "../constants/deployConfigTestnet";
import { EnvFileName } from "../types/deploymentVariables";
import {
	IDeployResult,
	genericDeploy,
	getNetworkEnvKey,
	getViemAccount,
	updateEnvVariable,
} from "../utils";

type DeployArgs = {
	defaultAdmin: string;
	minter: string;
	decimals: number;
};

type DeploymentFunction = (
	hre: HardhatRuntimeEnvironment,
	overrideArgs?: Partial<DeployArgs>,
) => Promise<IDeployResult>;

export const deployIOUToken: DeploymentFunction = async (
	hre: HardhatRuntimeEnvironment,
	overrideArgs?: Partial<DeployArgs>,
): Promise<IDeployResult> => {
	const { name } = hre.network;
	const chain = conceroNetworks[name as keyof typeof conceroNetworks];

	const viemAccount = getViemAccount(chain.type, "deployer");
	const deployer = viemAccount.address;

	const args: DeployArgs = {
		defaultAdmin: overrideArgs?.defaultAdmin || deployer,
		minter: overrideArgs?.minter || deployer,
		decimals: overrideArgs?.decimals || liqTokenDecimals,
	};

	let gasLimit = 0;
	const config = DEPLOY_CONFIG_TESTNET[name];
	if (config) {
		gasLimit = config.childPool?.gasLimit || 0;
	}

	const deployment = await genericDeploy(
		{
			hre,
			contractName: "IOUToken",
			txParams: {
				gasLimit: BigInt(gasLimit),
			},
		},
		args.defaultAdmin,
		args.minter,
		args.decimals,
	);

	updateEnvVariable(
		`IOU_${getNetworkEnvKey(deployment.chainName)}`,
		deployment.address,
		`deployments.${deployment.chainType}` as EnvFileName,
	);

	return deployment;
};
