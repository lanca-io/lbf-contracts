import { task } from "hardhat/config";

import { type HardhatRuntimeEnvironment } from "hardhat/types";
import { encodeFunctionData } from "viem";

import { ProxyEnum, lancaProxyAbi } from "../../constants";
import { deployChildPool } from "../../deploy/ChildPool";
import { deployIOUToken } from "../../deploy/IOUToken";
import { deployTransparentProxy } from "../../deploy/TransparentProxy";
import { err, getEnvVar } from "../../utils";
import { compileContracts } from "../../utils/compileContracts";
import { grantMinterRoleForIOUToken } from "../utils/grantMinterRoleForIOUToken";
import { setAllDstPools } from "../utils/setAllDstPools";
import { setFeeBps } from "../utils/setFeeBps";
import { setLibs } from "../utils/setLibs";
import { upgradeProxyImplementation } from "../utils/upgradeProxyImplementation";

async function deployChildPoolTask(taskArgs: any, hre: HardhatRuntimeEnvironment) {
	compileContracts({ quiet: true });

	if (taskArgs.iou) {
		await deployIOUToken(hre, {
			defaultAdmin: taskArgs.admin,
			minter: taskArgs.minter,
			decimals: taskArgs.decimals,
		});
	}

	if (taskArgs.implementation) {
		await deployChildPool(hre, {
			liquidityTokenGasOverhead: taskArgs.gasoverhead,
		});
	}

	if (taskArgs.proxy) {
		const [deployer] = await hre.ethers.getSigners();
		const lancaKeeperAddress = getEnvVar(`LANCA_KEEPER`);
		if (!lancaKeeperAddress) {
			err("Missing LANCA_KEEPER address", "deployTransparentProxy", hre.network.name);
			return;
		}
		const callData = encodeFunctionData({
			abi: lancaProxyAbi,
			functionName: "initialize",
			args: [deployer.address, lancaKeeperAddress],
		});
		await deployTransparentProxy(hre, ProxyEnum.childPoolProxy, callData);
	}

	if (taskArgs.implementation) {
		await upgradeProxyImplementation(hre, ProxyEnum.childPoolProxy, false);
	}

	if (taskArgs.vars) {
		await setLibs(hre.network.name);
		await setFeeBps(hre.network.name);
		await grantMinterRoleForIOUToken(hre.network.name);
		await setAllDstPools(hre.network.name);
	}
}

task("deploy-child-pool", "Deploy ChildPool")
	.addFlag("proxy", "Deploy proxy")
	.addFlag("implementation", "Deploy implementation")
	.addFlag("iou", "Deploy IOU Token")
	.addFlag("vars", "Set variables")
	.addOptionalParam("decimals", "Token decimals (IOU)")
	.addOptionalParam("gasoverhead", "Liquidity token gas overhead")
	.setAction(async (taskArgs, hre: HardhatRuntimeEnvironment) => {
		await deployChildPoolTask(taskArgs, hre);
	});

export { deployChildPoolTask };
