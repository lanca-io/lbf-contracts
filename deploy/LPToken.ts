import { HardhatRuntimeEnvironment } from "hardhat/types";

import { conceroNetworks, liqTokenDecimals } from "../constants";
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

export const deployLPToken: DeploymentFunction = async (
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

	const deployment = await genericDeploy(
		{
			hre,
			contractName: "LPToken",
		},
		args.defaultAdmin,
		args.minter,
		args.decimals,
	);

	updateEnvVariable(
		`LPT_${getNetworkEnvKey(deployment.chainName)}`,
		deployment.address,
		`deployments.${deployment.chainType}` as EnvFileName,
	);

	return deployment;
};
