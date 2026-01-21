import { task } from "hardhat/config";

import { getNetworkEnvKey } from "@concero/contract-utils";
import { type HardhatRuntimeEnvironment } from "hardhat/types";
import { erc20Abi, parseUnits } from "viem";

import { conceroNetworks } from "../../constants";
import { liqTokenDecimals } from "../../constants/deploymentVariables";
import { compileContracts, getEnvAddress, getEnvVar, getFallbackClients } from "../../utils";

async function withdrawFromParentPool(amount: string, networkName: string) {
	const { walletClient, publicClient } = getFallbackClients(conceroNetworks[networkName]);
	const { abi: parentPoolAbi } = await import(
		"../../artifacts/contracts/ParentPool/ParentPool.sol/ParentPool.json"
	);
	const parentPoolAddress = getEnvAddress("parentPoolProxy", networkName)[0];

	let hash = await walletClient.writeContract({
		abi: erc20Abi,
		functionName: "approve",
		address: getEnvVar(`LPT_${getNetworkEnvKey(networkName)}`),
		args: [parentPoolAddress, parseUnits(amount, liqTokenDecimals)],
	});

	const { status: approveStatus } = await publicClient.waitForTransactionReceipt({ hash });

	console.log("approve", approveStatus, hash);

	hash = await walletClient.writeContract({
		abi: parentPoolAbi,
		functionName: "enterWithdrawalQueue",
		address: parentPoolAddress,
		args: [parseUnits(amount, liqTokenDecimals)],
	});

	const { status } = await publicClient.waitForTransactionReceipt({ hash });

	console.log("enterWithdrawalQueue", status, hash);
}

task("withdraw-from-parent-pool", "withdraw from parent pool")
	.addParam("amount", "formatted amount (1.443)")
	.setAction(async (taskArgs, hre: HardhatRuntimeEnvironment) => {
		compileContracts({ quiet: true });

		await withdrawFromParentPool(taskArgs.amount, hre.network.name);
	});

export default {};
