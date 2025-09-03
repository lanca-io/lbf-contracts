import { getNetworkEnvKey, hardhatDeployWrapper } from "@concero/contract-utils";
import { Deployment } from "hardhat-deploy/types";
import { HardhatRuntimeEnvironment } from "hardhat/types";

import { conceroNetworks } from "../constants";
import { DEPLOY_CONFIG_TESTNET } from "../constants/deployConfigTestnet";
import { getFallbackClients, getViemAccount, log, updateEnvVariable } from "../utils";

type DeployArgs = {
	defaultAdmin: string;
	minter: string;
};

type DeploymentFunction = (
	hre: HardhatRuntimeEnvironment,
	overrideArgs?: Partial<DeployArgs>,
) => Promise<Deployment>;

const deployIOUToken: DeploymentFunction = async function (
	hre: HardhatRuntimeEnvironment,
	overrideArgs?: Partial<DeployArgs>,
): Promise<Deployment> {
	const { name } = hre.network;

	const chain = conceroNetworks[name as keyof typeof conceroNetworks];

	const viemAccount = getViemAccount(chain.type, "deployer");
	const { publicClient } = getFallbackClients(chain, viemAccount);
	const deployer = viemAccount.address;

	const args: DeployArgs = {
		defaultAdmin: overrideArgs?.defaultAdmin || deployer,
		minter: overrideArgs?.minter || deployer,
	};

	let gasLimit = 0;
	const config = DEPLOY_CONFIG_TESTNET[name];
	if (config) {
		gasLimit = config.childPool?.gasLimit || 0;
	}

	const deployment = await hardhatDeployWrapper("IOUToken", {
		hre,
		args: [args.defaultAdmin, args.minter],
		publicClient,
		gasLimit,
		skipIfAlreadyDeployed: true,
	});

	log(`IOUToken deployed at: ${deployment.address}`, "deployIOUToken", name);
	log(`Args: ${JSON.stringify(args)}`, "deployIOUToken", name);
	updateEnvVariable(
		`IOU_${getNetworkEnvKey(name)}`,
		deployment.address,
		`deployments.${chain.type}`,
	);

	return deployment;
};

deployIOUToken.tags = ["IOUToken"];

export default deployIOUToken;
export { deployIOUToken };
