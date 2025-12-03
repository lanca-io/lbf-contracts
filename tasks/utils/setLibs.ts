import { getNetworkEnvKey } from "@concero/contract-utils";

import { ADDRESS_ZERO, conceroNetworks, getViemReceiptConfig } from "../../constants";
import { err, getEnvVar, getFallbackClients, getViemAccount, log } from "../../utils";
import { isParentPoolNetwork } from "./isParentPoolNetwork";

export async function setLibs(srcChainName: string): Promise<void> {
	const srcChain = conceroNetworks[srcChainName as keyof typeof conceroNetworks];
	const { viemChain, type: networkType } = srcChain;

	const prefix = isParentPoolNetwork(srcChainName) ? "PARENT_POOL_PROXY_" : "CHILD_POOL_PROXY_";
	const contractAddress = getEnvVar(`${prefix}${getNetworkEnvKey(srcChainName)}`);

	if (!contractAddress) {
		err(`Contract address not found for ${srcChainName}`, "setLibs", srcChainName);
		return;
	}

	const { abi: baseAbi } = await import("../../artifacts/contracts/Base/Base.sol/Base.json");

	const viemAccount = getViemAccount(networkType, "proxyDeployer");
	const { walletClient, publicClient } = getFallbackClients(srcChain, viemAccount);

	const currentValidatorLib = await publicClient.readContract({
		address: contractAddress as `0x${string}`,
		abi: baseAbi,
		functionName: "getValidatorLib",
	});

	if (currentValidatorLib && currentValidatorLib.toString() !== ADDRESS_ZERO) {
		log(`Validator lib already set: ${currentValidatorLib}`, "setLibs", srcChainName);
	} else {
		const validatorLib = getEnvVar(
			`CONCERO_CRE_VALIDATOR_LIB_PROXY_${getNetworkEnvKey(srcChainName)}`,
		);

		if (!validatorLib) {
			err(`Validator lib not found for ${srcChainName}`, "setLibs", srcChainName);
			return;
		}

		try {
			const validatorLibTxHash = await walletClient.writeContract({
				address: contractAddress as `0x${string}`,
				abi: baseAbi,
				functionName: "setValidatorLib",
				account: viemAccount,
				args: [validatorLib],
				chain: viemChain,
			});

			const validatorLibReceipt = await publicClient.waitForTransactionReceipt({
				...getViemReceiptConfig(srcChain),
				hash: validatorLibTxHash,
			});

			log(
				`Validator lib set with status: ${validatorLibReceipt.status}! txHash: ${validatorLibReceipt.transactionHash}`,
				"setLibs",
				srcChainName,
			);
		} catch (error) {
			err(`Failed to set validator lib: ${error}`, "setLibs", srcChainName);
			throw error;
		}
	}

	const currentRelayerLib = await publicClient.readContract({
		address: contractAddress as `0x${string}`,
		abi: baseAbi,
		functionName: "getRelayerLib",
	});

	if (currentRelayerLib && currentRelayerLib.toString() !== ADDRESS_ZERO) {
		log(`Relayer lib already set: ${currentRelayerLib}`, "setLibs", srcChainName);
		return;
	}

	const relayerLib = getEnvVar(`CONCERO_RELAYER_LIB_PROXY_${getNetworkEnvKey(srcChainName)}`);

	if (!relayerLib) {
		err(`Relayer lib not found for ${srcChainName}`, "setLibs", srcChainName);
		return;
	}

	try {
		const relayerLibTxHash = await walletClient.writeContract({
			address: contractAddress as `0x${string}`,
			abi: baseAbi,
			functionName: "setRelayerLib",
			account: viemAccount,
			args: [relayerLib],
			chain: viemChain,
		});

		const relayerLibReceipt = await publicClient.waitForTransactionReceipt({
			...getViemReceiptConfig(srcChain),
			hash: relayerLibTxHash,
		});

		log(
			`Relayer lib set with status: ${relayerLibReceipt.status}! txHash: ${relayerLibReceipt.transactionHash}`,
			"setLibs",
			srcChainName,
		);
	} catch (error) {
		err(`Failed to set relayer lib: ${error}`, "setLibs", srcChainName);
		throw error;
	}

	log(`Libs set successfully for ${srcChainName}`, "setLibs", srcChainName);
}
