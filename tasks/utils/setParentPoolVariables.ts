import { getNetworkEnvKey } from "@concero/contract-utils";

import { conceroNetworks } from "../../constants";
import { parentPoolVariables } from "../../constants/deploymentVariables";
import { getEnvVar, getFallbackClients, getViemAccount, log } from "../../utils";

export async function setParentPoolVariables(name: string) {
	const chain = conceroNetworks[name as keyof typeof conceroNetworks];
	const viemAccount = getViemAccount(chain.type, "deployer");
	const { walletClient, publicClient } = getFallbackClients(chain, viemAccount);

	const parentPoolProxyAddress = getEnvVar(`PARENT_POOL_PROXY_${getNetworkEnvKey(name)}`);

	if (!parentPoolProxyAddress) {
		throw new Error("Missing required addresses for setting variables");
	}

	const { abi: parentPoolAbi } = await import(
		"../../artifacts/contracts/ParentPool/ParentPool.sol/ParentPool.json"
	);

	const args = {
		targetDepositQueueLength: parentPoolVariables.targetDepositQueueLength,
		targetWithdrawalQueueLength: parentPoolVariables.targetWithdrawalQueueLength,
		lurScoreSensitivity: parentPoolVariables.lurScoreSensitivity,
		lurScoreWeight: parentPoolVariables.lurScoreWeight,
		ndrScoreWeight: parentPoolVariables.ndrScoreWeight,
	};

	// Target deposit queue length
	try {
		const currentTargetDepositQueueLength = await publicClient.readContract({
			address: parentPoolProxyAddress,
			abi: parentPoolAbi,
			functionName: "getTargetDepositQueueLength",
		});

		if (currentTargetDepositQueueLength !== args.targetDepositQueueLength) {
			const setTargetDepositQueueLength = await walletClient.writeContract({
				address: parentPoolProxyAddress,
				abi: parentPoolAbi,
				functionName: "setTargetDepositQueueLength",
				args: [args.targetDepositQueueLength],
			});

			log(
				`Set target deposit queue length to ${args.targetDepositQueueLength}, hash: ${setTargetDepositQueueLength}`,
				"setParentPoolVariables",
				name,
			);
		} else {
			log(
				`Target deposit queue length already set to ${args.targetDepositQueueLength}`,
				"setParentPoolVariables",
				name,
			);
		}
	} catch (error) {
		log(
			`Failed to set target deposit queue length: ${error.message}`,
			"setParentPoolVariables",
			name,
		);
	}

	// Target withdrawal queue length
	try {
		const currentTargetWithdrawalQueueLength = await publicClient.readContract({
			address: parentPoolProxyAddress,
			abi: parentPoolAbi,
			functionName: "getTargetWithdrawalQueueLength",
		});

		if (currentTargetWithdrawalQueueLength !== args.targetWithdrawalQueueLength) {
			const setTargetWithdrawalQueueLengthHash = await walletClient.writeContract({
				address: parentPoolProxyAddress,
				abi: parentPoolAbi,
				functionName: "setTargetWithdrawalQueueLength",
				args: [args.targetWithdrawalQueueLength],
			});

			log(
				`Set target withdrawal queue length to ${args.targetWithdrawalQueueLength}, hash: ${setTargetWithdrawalQueueLengthHash}`,
				"setParentPoolVariables",
				name,
			);
		} else {
			log(
				`Target withdrawal queue length already set to ${args.targetWithdrawalQueueLength}`,
				"setParentPoolVariables",
				name,
			);
		}
	} catch (error) {
		log(
			`Failed to set target withdrawal queue length: ${error.message}`,
			"setParentPoolVariables",
			name,
		);
	}

	// Lur score sensitivity
	try {
		const currentLurScoreSensitivity = await publicClient.readContract({
			address: parentPoolProxyAddress,
			abi: parentPoolAbi,
			functionName: "getLurScoreSensitivity",
			args: [],
		});

		if (currentLurScoreSensitivity !== args.lurScoreSensitivity) {
			const setLurScoreSensitivityHash = await walletClient.writeContract({
				address: parentPoolProxyAddress,
				abi: parentPoolAbi,
				functionName: "setLurScoreSensitivity",
				args: [args.lurScoreSensitivity],
			});

			log(
				`Set lur score sensitivity to ${args.lurScoreSensitivity}, hash: ${setLurScoreSensitivityHash}`,
				"setParentPoolVariables",
				name,
			);
		} else {
			log(
				`Lur score sensitivity already set to ${args.lurScoreSensitivity}`,
				"setParentPoolVariables",
				name,
			);
		}
	} catch (error) {
		log(
			`Failed to set lur score sensitivity: ${error.message}`,
			"setParentPoolVariables",
			name,
		);
	}

	// Scores weights
	try {
		const [, currentNdrScoreWeight] = await publicClient.readContract({
			address: parentPoolProxyAddress,
			abi: parentPoolAbi,
			functionName: "getScoresWeights",
			args: [],
		});

		if (currentNdrScoreWeight !== args.ndrScoreWeight) {
			const setScoresWeightsHash = await walletClient.writeContract({
				address: parentPoolProxyAddress,
				abi: parentPoolAbi,
				functionName: "setScoresWeights",
				args: [args.lurScoreWeight, args.ndrScoreWeight],
			});

			log(
				`Set scores weights to ${args.lurScoreWeight} and ${args.ndrScoreWeight}, hash: ${setScoresWeightsHash}`,
				"setParentPoolVariables",
				name,
			);
		} else {
			log(
				`Weights already set to ${args.lurScoreWeight} and ${args.ndrScoreWeight}`,
				"setParentPoolVariables",
				name,
			);
		}
	} catch (error) {
		log(`Failed to set scores weights: ${error.message}`, "setParentPoolVariables", name);
	}
}
