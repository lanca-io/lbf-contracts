import { getNetworkEnvKey } from "@concero/contract-utils";
import { Deployment } from "hardhat-deploy/types";
import { HardhatRuntimeEnvironment } from "hardhat/types";

import { conceroNetworks } from "../constants";
import { log, updateEnvVariable } from "../utils";

type DeploymentFunction = (hre: HardhatRuntimeEnvironment) => Promise<Deployment>;

const deployMockUSDC: DeploymentFunction = async function (
	hre: HardhatRuntimeEnvironment,
): Promise<Deployment> {
	const { deployer } = await hre.getNamedAccounts();
	const { deploy } = hre.deployments;
	const { name } = hre.network;

	const chain = conceroNetworks[name as keyof typeof conceroNetworks];
	const { type: networkType } = chain;

	const nameArg = "USD Coin";
	const symbolArg = "USDC";
	const decimalsArg = 6;

	const args = [nameArg, symbolArg, decimalsArg];

	const deployment = await deploy("MockERC20", {
		from: deployer,
		contract: "MockERC20",
		args,
		log: true,
		autoMine: true,
		skipIfAlreadyDeployed: true,
	});

	log(`MockUSDC deployed at: ${deployment.address}`, "deployMockUSDC", name);
	log(
		`Args: 
			name: ${nameArg}, 
			symbol: ${symbolArg}, 
			decimals: ${decimalsArg}`,
		"deployMockUSDC",
		name,
	);
	updateEnvVariable(
		`FIAT_TOKEN_PROXY_${getNetworkEnvKey(name)}`,
		deployment.address,
		`deployments.${networkType}`,
	);

	return deployment;
};

deployMockUSDC.tags = ["MockUSDC"];

export default deployMockUSDC;
export { deployMockUSDC };
