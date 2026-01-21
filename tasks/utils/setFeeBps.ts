import { conceroNetworks } from "../../constants";
import { poolFeeBps } from "../../constants/deploymentVariables";
import {
	err,
	getEnvVar,
	getFallbackClients,
	getNetworkEnvKey,
	getViemAccount,
	log,
	warn,
} from "../../utils";
import { isParentPoolNetwork } from "./isParentPoolNetwork";

export async function setFeeBps(name: string) {
	const chain = conceroNetworks[name as keyof typeof conceroNetworks];
	const viemAccount = getViemAccount(chain.type, "deployer");
	const { walletClient, publicClient } = getFallbackClients(chain, viemAccount);

	const prefix = isParentPoolNetwork(name) ? "PARENT_POOL_PROXY_" : "CHILD_POOL_PROXY_";
	const contractAddress = getEnvVar(`${prefix}${getNetworkEnvKey(name)}`);

	if (!contractAddress) {
		throw new Error("Missing required addresses for setting fee bps");
	}

	const { abi: baseAbi } = await import("../../artifacts/contracts/Base/Base.sol/Base.json");

	const args = {
		rebalancerFeeBps: poolFeeBps.rebalancerFeeBps,
		lpFeeBps: poolFeeBps.lpFeeBps,
		lancaBridgeFeeBps: poolFeeBps.lancaBridgeFeeBps,
	};

	// Warn if any fee is set to 0
	if (args.rebalancerFeeBps === 0) {
		err("rebalancerFeeBps is set to 0 in constants", "setFeeBps", name);
	}
	if (args.lpFeeBps === 0) {
		err("lpFeeBps is set to 0 in constants", "setFeeBps", name);
	}
	if (args.lancaBridgeFeeBps === 0) {
		err("lancaBridgeFeeBps is set to 0 in constants", "setFeeBps", name);
	}

	// Rebalancer fee bps
	try {
		const currentRebalancerFeeBps = await publicClient.readContract({
			address: contractAddress,
			abi: baseAbi,
			functionName: "getRebalancerFeeBps",
		});

		if (currentRebalancerFeeBps !== args.rebalancerFeeBps) {
			const setRebalancerFeeBpsHash = await walletClient.writeContract({
				address: contractAddress,
				abi: baseAbi,
				functionName: "setRebalancerFeeBps",
				args: [args.rebalancerFeeBps],
			});

			log(
				`Set rebalancer fee bps to ${args.rebalancerFeeBps}, hash: ${setRebalancerFeeBpsHash}`,
				"setFeeBps",
				name,
			);
		} else {
			warn(`Rebalancer fee bps already set to ${args.rebalancerFeeBps}`, "setFeeBps", name);
		}
	} catch (error) {
		err(`Failed to set rebalancer fee bps: ${error.message}`, "setFeeBps", name);
	}

	// LP fee bps
	try {
		const currentLpFeeBps = await publicClient.readContract({
			address: contractAddress,
			abi: baseAbi,
			functionName: "getLpFeeBps",
		});

		if (currentLpFeeBps !== args.lpFeeBps) {
			const setLpFeeBpsHash = await walletClient.writeContract({
				address: contractAddress,
				abi: baseAbi,
				functionName: "setLpFeeBps",
				args: [args.lpFeeBps],
			});

			log(`Set lp fee bps to ${args.lpFeeBps}, hash: ${setLpFeeBpsHash}`, "setFeeBps", name);
		} else {
			warn(`LP fee bps already set to ${args.lpFeeBps}`, "setFeeBps", name);
		}
	} catch (error) {
		err(`Failed to set lp fee bps: ${error.message}`, "setFeeBps", name);
	}

	// Lanca bridge fee bps
	try {
		const currentLancaBridgeFeeBps = await publicClient.readContract({
			address: contractAddress,
			abi: baseAbi,
			functionName: "getLancaBridgeFeeBps",
		});

		if (currentLancaBridgeFeeBps !== args.lancaBridgeFeeBps) {
			const setLancaBridgeFeeBpsHash = await walletClient.writeContract({
				address: contractAddress,
				abi: baseAbi,
				functionName: "setLancaBridgeFeeBps",
				args: [args.lancaBridgeFeeBps],
			});

			log(
				`Set lanca bridge fee bps to ${args.lancaBridgeFeeBps}, hash: ${setLancaBridgeFeeBpsHash}`,
				"setFeeBps",
				name,
			);
		} else {
			warn(
				`Lanca bridge fee bps already set to ${args.lancaBridgeFeeBps}`,
				"setFeeBps",
				name,
			);
		}
	} catch (error) {
		err(`Failed to set lanca bridge fee bps: ${error.message}`, "setFeeBps", name);
	}
}
