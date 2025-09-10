import { task } from "hardhat/config";

import { execSync } from "child_process";

import { getNetworkEnvKey } from "@concero/contract-utils";

import { conceroNetworks } from "../constants";
import { getEnvVar } from "../utils";

task("update-all-child-pool-implementations").setAction(async (taskArgs, hre) => {
	for (const network in conceroNetworks) {
		const childPool = getEnvVar(`CHILD_POOL_PROXY_${getNetworkEnvKey(network)}`);

		if (!childPool) {
			continue;
		}

		try {
			execSync(`yarn hardhat deploy-child-pool --implementation --network ${network}`, {
				encoding: "utf8",
				stdio: "inherit",
			});
		} catch (error) {
			console.error(`Command failed for ${network}:`, error.stderr || error.message);
		}
	}
});

export default {};
