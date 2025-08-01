import { task } from "hardhat/config";

import { getNetworkEnvKey } from "@concero/contract-utils";
import { type HardhatRuntimeEnvironment } from "hardhat/types";

import { conceroNetworks } from "../constants";
import { deployParentPool } from "../deploy/02_deploy_parentpool";
import { deployProxyAdmin } from "../deploy/utils/deployProxyAdmin";
import { deployTransparentProxy } from "../deploy/utils/deployTransparentProxy";
import { getEnvVar } from "../utils";
import { getFallbackClients } from "../utils";
import { compileContracts } from "../utils/compileContracts";

export async function setParentPoolVariables(hre: HardhatRuntimeEnvironment) {
	const { name } = hre.network;
	const chain = conceroNetworks[name];
	const { walletClient } = getFallbackClients(chain);
	const { deployer } = await hre.getNamedAccounts();

	const parentPoolAddress = getEnvVar(`PARENT_POOL_${getNetworkEnvKey(name)}`);
	const lpTokenAddress = getEnvVar(`LPT_${getNetworkEnvKey(name)}`);
	const iouTokenAddress = getEnvVar(`IOU_${getNetworkEnvKey(name)}`);

	if (!parentPoolAddress || !lpTokenAddress || !iouTokenAddress) {
		throw new Error("Missing required addresses for setting variables");
	}

	const MINTER_ROLE = hre.ethers.keccak256(hre.ethers.toUtf8Bytes("MINTER_ROLE"));
	const grantRoleAbi = [
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
	];

	// Grant MINTER_ROLE to ParentPool on LPToken
	await walletClient.writeContract({
		address: lpTokenAddress,
		abi: grantRoleAbi,
		functionName: "grantRole",
		args: [MINTER_ROLE, parentPoolAddress],
		account: deployer,
	});

	// Grant MINTER_ROLE to ParentPool on IOUToken
	await walletClient.writeContract({
		address: iouTokenAddress,
		abi: grantRoleAbi,
		functionName: "grantRole",
		args: [MINTER_ROLE, parentPoolAddress],
		account: deployer,
	});
}

async function deployParentPoolTask(taskArgs: any, hre: HardhatRuntimeEnvironment) {
	compileContracts({ quiet: true });

	let deployment;

	if (taskArgs.implementation) {
		deployment = await deployParentPool(hre, taskArgs.deployOptions);

		if (taskArgs.proxy) {
			const proxyAdmin = await deployProxyAdmin(hre, "PARENT_POOL");
			await deployTransparentProxy(
				hre,
				"PARENT_POOL",
				deployment.address,
				proxyAdmin.address,
			);
		}
	}

	if (taskArgs.vars) {
		await setParentPoolVariables(hre);
	}

	return deployment;
}

task("deploy-parent-pool", "Deploy ParentPool")
	.addFlag("proxy", "Deploy proxy")
	.addFlag("implementation", "Deploy implementation")
	.addFlag("vars", "Set contract variables")
	.setAction(async (taskArgs, hre: HardhatRuntimeEnvironment) => {
		await deployParentPoolTask(taskArgs, hre);
	});

export { deployParentPoolTask };
