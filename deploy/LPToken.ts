import { getNetworkEnvKey } from "@concero/contract-utils";
import { Deployment } from "hardhat-deploy/types";
import { HardhatRuntimeEnvironment } from "hardhat/types";

import { conceroNetworks, liqTokenDecimals } from "../constants";
import { getFallbackClients, getViemAccount, log, updateEnvVariable } from "../utils";

type DeployArgs = {
	defaultAdmin: string;
	minter: string;
	decimals: number;
};

type DeploymentFunction = (
	hre: HardhatRuntimeEnvironment,
	overrideArgs?: Partial<DeployArgs>,
) => Promise<Deployment>;

const deployLPToken: DeploymentFunction = async function (
	hre: HardhatRuntimeEnvironment,
	overrideArgs?: Partial<DeployArgs>,
): Promise<Deployment> {
	const { deploy } = hre.deployments;
	const { name } = hre.network;

	const chain = conceroNetworks[name as keyof typeof conceroNetworks];

	const viemAccount = getViemAccount(chain.type, "deployer");
	const deployer = viemAccount.address;

	const args: DeployArgs = {
		defaultAdmin: overrideArgs?.defaultAdmin || deployer,
		minter: overrideArgs?.minter || deployer,
		decimals: overrideArgs?.decimals || liqTokenDecimals,
	};

	const deployment = await deploy("LPToken", {
		from: deployer,
		args: [args.defaultAdmin, args.minter, args.decimals],
		log: true,
		autoMine: true,
		skipIfAlreadyDeployed: true,
	});

	log(`LPToken deployed at: ${deployment.address}`, "deployLPToken", name);
	log(`Args: ${JSON.stringify(args)}`, "deployLPToken", name);
	updateEnvVariable(
		`LPT_${getNetworkEnvKey(name)}`,
		deployment.address,
		`deployments.${chain.type}`,
	);

	return deployment;
};

deployLPToken.tags = ["LPToken"];

export default deployLPToken;
export { deployLPToken };
