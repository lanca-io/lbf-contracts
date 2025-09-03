import { task } from "hardhat/config";

import { getNetworkEnvKey } from "@concero/contract-utils";
import { type HardhatRuntimeEnvironment } from "hardhat/types";
import { erc20Abi, parseUnits } from "viem";

import { conceroNetworks } from "../../constants";
import { liqTokenDecimals } from "../../constants/deploymentVariables";
import { compileContracts, getEnvAddress, getEnvVar, getFallbackClients } from "../../utils";
import { isParentPoolNetwork } from "../utils/isParentPoolNetwork";

async function sendBridge(amount: string, srcChainName: string, dstChainName: string) {
	const { walletClient, publicClient } = getFallbackClients(conceroNetworks[srcChainName]);
	const { abi: parentPoolAbi } = await import(
		"../../artifacts/contracts/ParentPool/ParentPool.sol/ParentPool.json"
	);
	const srcPool = isParentPoolNetwork(srcChainName)
		? getEnvAddress("parentPoolProxy", srcChainName)[0]
		: getEnvAddress("childPoolProxy", srcChainName)[0];

	const dstPool = isParentPoolNetwork(dstChainName)
		? getEnvAddress("parentPoolProxy", dstChainName)[0]
		: getEnvAddress("childPoolProxy", dstChainName)[0];

	let hash = await walletClient.writeContract({
		abi: erc20Abi,
		functionName: "approve",
		address: getEnvVar(`USDC_PROXY_${getNetworkEnvKey(srcChainName)}`),
		args: [srcPool, parseUnits(amount, liqTokenDecimals)],
	});

	const { status: approveStatus } = await publicClient.waitForTransactionReceipt({ hash });

	console.log("approve", approveStatus, hash);

	hash = await walletClient.writeContract({
		abi: parentPoolAbi,
		functionName: "bridge",
		address: srcPool,
		chain: walletClient.chain,
		account: walletClient.account!,
		value: (await publicClient.readContract({
			abi: parentPoolAbi,
			functionName: "getBridgeNativeFee",
			address: srcPool,
			args: [conceroNetworks[dstChainName].chainSelector, dstPool, 0n],
		})) as bigint,
		args: [
			walletClient.account?.address!,
			parseUnits(amount, liqTokenDecimals),
			conceroNetworks[dstChainName].chainSelector,
			0n,
			"",
		],
	});

	const { status } = await publicClient.waitForTransactionReceipt({ hash });

	console.log("bridge", status, hash);
}

task("send-bridge", "")
	.addParam("amount", "formatted amount (1.443)")
	.addParam("dst", "dst chain name")
	.setAction(async (taskArgs, hre: HardhatRuntimeEnvironment) => {
		compileContracts({ quiet: true });

		await sendBridge(taskArgs.amount, hre.network.name, taskArgs.dst);
	});

export default {};
