import { hardhatDeployWrapper } from "@concero/contract-utils";
import { Deployment } from "hardhat-deploy/types";
import { HardhatRuntimeEnvironment } from "hardhat/types";

import { conceroNetworks } from "../constants";
import { DEPLOY_CONFIG_TESTNET } from "../constants/deployConfigTestnet";
import { IProxyType } from "../types/deploymentVariables";
import { getFallbackClients, getViemAccount, getWallet, log, updateEnvAddress } from "../utils";

export async function deployProxyAdmin(
	hre: HardhatRuntimeEnvironment,
	proxyType: IProxyType,
): Promise<Deployment> {
	const { name } = hre.network;

	const chain = conceroNetworks[name as keyof typeof conceroNetworks];
	const { type: networkType } = chain;

	const viemAccount = getViemAccount(chain.type, "proxyDeployer");
	const { publicClient } = getFallbackClients(chain, viemAccount);
	const initialOwner = viemAccount.address;

	let gasLimit = 0;
	const config = DEPLOY_CONFIG_TESTNET[name];
	if (config) {
		gasLimit = config.proxy?.gasLimit || 0;
	}

	const deployment = await hardhatDeployWrapper("LancaProxyAdmin", {
		hre,
		args: [initialOwner],
		publicClient,
		gasLimit,
		proxy: true,
	});

	log(
		`Deployed at: ${deployment.address}. initialOwner: ${initialOwner}`,
		`deployProxyAdmin: ${proxyType}`,
		name,
	);
	updateEnvAddress(`${proxyType}Admin`, name, deployment.address, `deployments.${networkType}`);

	return deployment;
}

deployProxyAdmin.tags = ["LancaProxyAdmin"];

export default deployProxyAdmin;
