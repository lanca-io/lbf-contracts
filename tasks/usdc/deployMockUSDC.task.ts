import { task } from "hardhat/config";

import { type HardhatRuntimeEnvironment } from "hardhat/types";

import { deployMockUSDC } from "../../deploy/MockUSDC";
import { compileContracts } from "../../utils";

async function deployMockUSDCTask(taskArgs: any, hre: HardhatRuntimeEnvironment) {
	compileContracts({ quiet: true });

	await deployMockUSDC(hre);
}

task("deploy-mock-usdc", "Deploy MockUSDC token").setAction(
	async (taskArgs, hre: HardhatRuntimeEnvironment) => {
		await deployMockUSDCTask(taskArgs, hre);
	},
);

export { deployMockUSDCTask };
