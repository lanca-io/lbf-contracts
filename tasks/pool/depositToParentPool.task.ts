import { task } from "hardhat/config";

import { getNetworkEnvKey } from "@concero/contract-utils";
import { type HardhatRuntimeEnvironment } from "hardhat/types";
import { erc20Abi, parseUnits } from "viem";

import { conceroNetworks } from "../../constants";
import { liqTokenDecimals } from "../../constants/deploymentVariables";
import { getEnvAddress, getEnvVar, getFallbackClients } from "../../utils";
import { compileContracts } from "../../utils/compileContracts";

async function depositToParentPool(amount: string, networkName: string) {
	const { walletClient, publicClient } = getFallbackClients(conceroNetworks[networkName]);
	const { abi: parentPoolAbi } = await import(
		"../../artifacts/contracts/ParentPool/ParentPool.sol/ParentPool.json"
	);
	const parentPoolAddress = getEnvAddress("parentPoolProxy", networkName)[0];

	let hash = await walletClient.writeContract({
		abi: erc20Abi,
		functionName: "approve",
		address: getEnvVar(`FIAT_TOKEN_PROXY_${getNetworkEnvKey(networkName)}`),
		args: [parentPoolAddress, parseUnits(amount, liqTokenDecimals)],
	});

	const { status: approveStatus } = await publicClient.waitForTransactionReceipt({ hash });

	console.log("approve", approveStatus, hash);

	hash = await walletClient.writeContract({
		abi: parentPoolAbi,
		functionName: "enterDepositQueue",
		address: parentPoolAddress,
		args: [parseUnits(amount, liqTokenDecimals)],
	});

	const { status } = await publicClient.waitForTransactionReceipt({ hash });

	console.log("enterDepositQueue", status, hash);
}

task("deposit-to-parent-pool", "deposit to parent pool")
	.addParam("amount")
	.setAction(async (taskArgs, hre: HardhatRuntimeEnvironment) => {
		compileContracts({ quiet: true });

		await depositToParentPool(taskArgs.amount, hre.network.name);
	});

export default {};
