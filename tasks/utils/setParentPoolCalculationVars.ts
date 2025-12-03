import { getNetworkEnvKey } from "@concero/contract-utils";

import { conceroNetworks } from "../../constants";
import { parentPoolVariables } from "../../constants/deploymentVariables";
import { err, getEnvVar, getFallbackClients, getViemAccount, log, warn } from "../../utils";

export async function setParentPoolCalculationVars(name: string) {
	const chain = conceroNetworks[name as keyof typeof conceroNetworks];
	const viemAccount = getViemAccount(chain.type, "proxyDeployer");
	const { walletClient, publicClient } = getFallbackClients(chain, viemAccount);

	const parentPoolProxyAddress = getEnvVar(`PARENT_POOL_PROXY_${getNetworkEnvKey(name)}`);

	if (!parentPoolProxyAddress) {
		throw new Error("Missing required addresses for setting variables");
	}

	const { abi: parentPoolAbi } = await import(
		"../../artifacts/contracts/ParentPool/ParentPool.sol/ParentPool.json"
	);

	const args = {
		minDepositQueueLength: parentPoolVariables.minDepositQueueLength,
		minWithdrawalQueueLength: parentPoolVariables.minWithdrawalQueueLength,
		lurScoreSensitivity: parentPoolVariables.lurScoreSensitivity,
		lurScoreWeight: parentPoolVariables.lurScoreWeight,
		ndrScoreWeight: parentPoolVariables.ndrScoreWeight,
		minDepositAmount: parentPoolVariables.minDepositAmount,
		minWithdrawalAmount: parentPoolVariables.minWithdrawalAmount,
		averageConceroMessageFee: parentPoolVariables.averageConceroMessageFee,
	};

	if (args.averageConceroMessageFee === 0n) {
		err("averageConceroMessageFee is set to 0 in constants", "setParentPoolVariables", name);
	}

	// Min deposit queue length
	try {
		const currentMinDepositQueueLength = await publicClient.readContract({
			address: parentPoolProxyAddress,
			abi: parentPoolAbi,
			functionName: "getMinDepositQueueLength",
		});

		if (currentMinDepositQueueLength !== args.minDepositQueueLength) {
			const setMinDepositQueueLength = await walletClient.writeContract({
				address: parentPoolProxyAddress,
				abi: parentPoolAbi,
				functionName: "setMinDepositQueueLength",
				args: [args.minDepositQueueLength],
			});

			log(
				`Set target deposit queue length to ${args.minDepositQueueLength}, hash: ${setMinDepositQueueLength}`,
				"setParentPoolVariables",
				name,
			);
		} else {
			warn(
				`Min deposit queue length already set to ${args.minDepositQueueLength}`,
				"setParentPoolVariables",
			);
		}
	} catch (error) {
		err(
			`Failed to set min deposit queue length: ${error.message}`,
			"setParentPoolVariables",
			name,
		);
	}

	// Min withdrawal queue length
	try {
		const currentMinWithdrawalQueueLength = await publicClient.readContract({
			address: parentPoolProxyAddress,
			abi: parentPoolAbi,
			functionName: "getMinWithdrawalQueueLength",
		});

		if (currentMinWithdrawalQueueLength !== args.minWithdrawalQueueLength) {
			const setTargetWithdrawalQueueLengthHash = await walletClient.writeContract({
				address: parentPoolProxyAddress,
				abi: parentPoolAbi,
				functionName: "setMinWithdrawalQueueLength",
				args: [args.minWithdrawalQueueLength],
			});

			log(
				`Set target withdrawal queue length to ${args.minWithdrawalQueueLength}, hash: ${setTargetWithdrawalQueueLengthHash}`,
				"setParentPoolVariables",
				name,
			);
		} else {
			warn(
				`Min withdrawal queue length already set to ${args.minWithdrawalQueueLength}`,
				"setParentPoolVariables",
			);
		}
	} catch (error) {
		err(`Failed to set min withdrawal queue length: ${error}`, "setParentPoolVariables", name);
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
			warn(
				`Lur score sensitivity already set to ${args.lurScoreSensitivity}`,
				"setParentPoolVariables",
			);
		}
	} catch (error) {
		err(
			`Failed to set lur score sensitivity: ${error.message}`,
			"setParentPoolVariables",
			name,
		);
	}

	// Scores weights
	try {
		const [lurScoreWeight, currentNdrScoreWeight] = await publicClient.readContract({
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
			warn(
				`Weights already set to ${args.lurScoreWeight} and ${args.ndrScoreWeight}`,
				"setParentPoolVariables",
			);
		}
	} catch (error) {
		err(`Failed to set scores weights: ${error.message}`, "setParentPoolVariables", name);
	}

	// Min deposit amount
	try {
		const currentMinDepositAmount = await publicClient.readContract({
			address: parentPoolProxyAddress,
			abi: parentPoolAbi,
			functionName: "getMinDepositAmount",
		});

		if (currentMinDepositAmount !== args.minDepositAmount) {
			const setMinDepositAmountHash = await walletClient.writeContract({
				address: parentPoolProxyAddress,
				abi: parentPoolAbi,
				functionName: "setMinDepositAmount",
				args: [args.minDepositAmount],
			});

			log(
				`Set min deposit amount to ${args.minDepositAmount}, hash: ${setMinDepositAmountHash}`,
				"setParentPoolVariables",
				name,
			);
		} else {
			warn(
				`Min deposit amount already set to ${args.minDepositAmount}`,
				"setParentPoolVariables",
				name,
			);
		}
	} catch (error) {
		err(`Failed to set min deposit amount: ${error.message}`, "setParentPoolVariables", name);
	}

	// Min withdrawal amount
	try {
		const currentMinWithdrawalAmount = await publicClient.readContract({
			address: parentPoolProxyAddress,
			abi: parentPoolAbi,
			functionName: "getMinWithdrawalAmount",
		});

		if (currentMinWithdrawalAmount !== args.minWithdrawalAmount) {
			const setMinWithdrawalAmountHash = await walletClient.writeContract({
				address: parentPoolProxyAddress,
				abi: parentPoolAbi,
				functionName: "setMinWithdrawalAmount",
				args: [args.minWithdrawalAmount],
			});

			log(
				`Set min withdrawal amount to ${args.minWithdrawalAmount}, hash: ${setMinWithdrawalAmountHash}`,
				"setParentPoolVariables",
				name,
			);
		} else {
			warn(
				`Min withdrawal amount already set to ${args.minWithdrawalAmount}`,
				"setParentPoolVariables",
			);
		}
	} catch (error) {
		err(
			`Failed to set min withdrawal amount: ${error.message}`,
			"setParentPoolVariables",
			name,
		);
	}

	// Average Concero message fee
	if (args.averageConceroMessageFee !== 0n) {
		try {
			const setAverageConceroMessageFeeHash = await walletClient.writeContract({
				address: parentPoolProxyAddress,
				abi: parentPoolAbi,
				functionName: "setAverageConceroMessageFee",
				args: [args.averageConceroMessageFee],
			});

			log(
				`Set average concero message fee to ${args.averageConceroMessageFee}, hash: ${setAverageConceroMessageFeeHash}`,
				"setParentPoolVariables",
				name,
			);
		} catch (error) {
			err(
				`Failed to set average concero message fee: ${error.message}`,
				"setParentPoolVariables",
				name,
			);
		}
	}
}
