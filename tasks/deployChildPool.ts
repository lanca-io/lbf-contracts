import { task } from "hardhat/config";

import { getNetworkEnvKey } from "@concero/contract-utils";
import { type HardhatRuntimeEnvironment } from "hardhat/types";

import { conceroNetworks } from "../constants";
import { deployChildPool } from "../deploy/03_deploy_childpool";
import { deployProxyAdmin } from "../deploy/utils/deployProxyAdmin";
import { deployTransparentProxy } from "../deploy/utils/deployTransparentProxy";
import { getEnvVar } from "../utils";
import { getFallbackClients } from "../utils";
import { compileContracts } from "../utils/compileContracts";

export async function setChildPoolVariables(hre: HardhatRuntimeEnvironment) {
	const { name } = hre.network;
	const chain = conceroNetworks[name];
	const { walletClient } = getFallbackClients(chain);
	const { deployer } = await hre.getNamedAccounts();

	const childPoolAddress = getEnvVar(`CHILD_POOL_${getNetworkEnvKey(name)}`);
	const iouTokenAddress = getEnvVar(`IOU_${getNetworkEnvKey(name)}`);

	if (!childPoolAddress || !iouTokenAddress) {
		throw new Error("Missing required addresses for setting variables");
	}

	const MINTER_ROLE = hre.ethers.keccak256(hre.ethers.toUtf8Bytes("MINTER_ROLE"));

	// Grant MINTER_ROLE to ChildPool on IOUToken
	await walletClient.writeContract({
		address: iouTokenAddress,
		abi: [
			{
				inputs: [
					{ internalType: "bytes32", name: "role", type: "bytes32" },
					{ internalType: "address", name: "account", type: "address" },
				],
				name: "grantRole",
				outputs: [],
				stateMutability: "nonpayable",
				type: "function",
			},
		],
		functionName: "grantRole",
		args: [MINTER_ROLE, childPoolAddress],
		account: deployer,
	});
}

async function deployChildPoolTask(taskArgs: any, hre: HardhatRuntimeEnvironment) {
	compileContracts({ quiet: true });

	let deployment;

	if (taskArgs.implementation) {
		deployment = await deployChildPool(hre, taskArgs.deployOptions);

		if (taskArgs.proxy) {
			const proxyAdmin = await deployProxyAdmin(hre, "CHILD_POOL");
			await deployTransparentProxy(hre, "CHILD_POOL", deployment.address, proxyAdmin.address);
		}
	}

	if (taskArgs.vars) {
		await setChildPoolVariables(hre);
	}

	return deployment;
}

task("deploy-child-pool", "Deploy ChildPool")
	.addFlag("proxy", "Deploy proxy")
	.addFlag("implementation", "Deploy implementation")
	.addFlag("vars", "Set contract variables")
	.setAction(async (taskArgs, hre: HardhatRuntimeEnvironment) => {
		await deployChildPoolTask(taskArgs, hre);
	});

export { deployChildPoolTask };
