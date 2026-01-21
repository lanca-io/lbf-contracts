import { HardhatRuntimeEnvironment } from "hardhat/types";

import { EnvFileName } from "../types/deploymentVariables";
import { IDeployResult, genericDeploy, getNetworkEnvKey, updateEnvVariable } from "../utils";

type DeploymentFunction = (hre: HardhatRuntimeEnvironment) => Promise<IDeployResult>;

export const deployMockUSDC: DeploymentFunction = async (
	hre: HardhatRuntimeEnvironment,
): Promise<IDeployResult> => {
	const nameArg = "USD Coin";
	const symbolArg = "USDC";
	const decimalsArg = 6;

	const args = [nameArg, symbolArg, decimalsArg];

	const deployment = await genericDeploy(
		{
			hre,
			contractName: "MockERC20",
		},
		args,
	);

	updateEnvVariable(
		`USDC_PROXY_${getNetworkEnvKey(deployment.chainName)}`,
		deployment.address,
		`deployments.${deployment.chainType}` as EnvFileName,
	);

	return deployment;
};
