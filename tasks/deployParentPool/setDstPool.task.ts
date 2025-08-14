import { task } from "hardhat/config";

import { type HardhatRuntimeEnvironment } from "hardhat/types";

import { compileContracts } from "../../utils/compileContracts";
import { setDstPool } from "../utils/setDstPool";

async function setDstPoolTask(taskArgs: any, hre: HardhatRuntimeEnvironment) {
	compileContracts({ quiet: true });

	const srcChainName = hre.network.name;

	await setDstPool(srcChainName, { dstChainName: taskArgs.dst });
}

task("set-dst-pool", "Set destination pool for ParentPool and ChildPool contracts")
	.addFlag("dst", "Address of the destination pool")
	.setAction(async (taskArgs, hre: HardhatRuntimeEnvironment) => {
		await setDstPoolTask(taskArgs, hre);
	});

export { setDstPoolTask };
