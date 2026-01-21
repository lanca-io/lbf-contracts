import { task } from "hardhat/config";

import { type HardhatRuntimeEnvironment } from "hardhat/types";

import { compileContracts } from "../utils";
import { setDstPool } from "./utils/setDstPool";

async function setDstPoolTask(taskArgs: any, hre: HardhatRuntimeEnvironment) {
	compileContracts({ quiet: true });

	const srcChainName = hre.network.name;

	await setDstPool(srcChainName, taskArgs.dst);
}

task("set-dst-pool", "Set destination pool for ParentPool and ChildPool contracts")
	.addParam("dst", "Name of the destination chain")
	.setAction(async (taskArgs, hre: HardhatRuntimeEnvironment) => {
		await setDstPoolTask(taskArgs, hre);
	});

export { setDstPoolTask };
