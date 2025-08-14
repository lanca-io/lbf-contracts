import { task } from "hardhat/config";

import { type HardhatRuntimeEnvironment } from "hardhat/types";

import { compileContracts } from "../utils/compileContracts";
import { setLancaKeeper } from "./utils/setLancaKeeper";

async function setLancaKeeperTask(taskArgs: any, hre: HardhatRuntimeEnvironment) {
	compileContracts({ quiet: true });

	const networkName = hre.network.name;

	await setLancaKeeper(networkName);
}

task("set-lanca-keeper", "Set LancaKeeper address for ParentPool or ChildPool").setAction(
	async (taskArgs, hre: HardhatRuntimeEnvironment) => {
		await setLancaKeeperTask(taskArgs, hre);
	},
);

export { setLancaKeeperTask };
