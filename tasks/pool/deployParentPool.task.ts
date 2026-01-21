import { task } from "hardhat/config";

import { type HardhatRuntimeEnvironment } from "hardhat/types";
import { encodeFunctionData } from "viem";

import { ProxyEnum, lancaProxyAbi } from "../../constants";
import { deployIOUToken } from "../../deploy/IOUToken";
import { deployLPToken } from "../../deploy/LPToken";
import { deployParentPool } from "../../deploy/ParentPool";
import { deployTransparentProxy } from "../../deploy/TransparentProxy";
import { compileContracts, err, getEnvVar } from "../../utils";
import { grantMinterRoleForIOUToken } from "../utils/grantMinterRoleForIOUToken";
import { grantMinterRoleForLPToken } from "../utils/grantMinterRoleForLPToken";
import { setAllDstPools } from "../utils/setAllDstPools";
import { setFeeBps } from "../utils/setFeeBps";
import { setLibs } from "../utils/setLibs";
import { setParentPoolCalculationVars } from "../utils/setParentPoolCalculationVars";
import { setParentPoolLiqCap } from "../utils/setParentPoolLiqCap";
import { upgradeProxyImplementation } from "../utils/upgradeProxyImplementation";

async function deployParentPoolTask(taskArgs: any, hre: HardhatRuntimeEnvironment) {
	compileContracts({ quiet: true });

	if (taskArgs.lp) {
		await deployLPToken(hre, {
			defaultAdmin: taskArgs.admin,
			minter: taskArgs.minter,
			decimals: taskArgs.decimals,
		});
	}

	if (taskArgs.iou) {
		await deployIOUToken(hre, {
			defaultAdmin: taskArgs.admin,
			minter: taskArgs.minter,
			decimals: taskArgs.decimals,
		});
	}

	if (taskArgs.implementation) {
		await deployParentPool(hre, {
			minTargetBalance: taskArgs.mtb,
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
		await deployTransparentProxy(hre, ProxyEnum.parentPoolProxy, callData);
	}

	if (taskArgs.implementation) {
		await upgradeProxyImplementation(hre, ProxyEnum.parentPoolProxy, false);
	}

	if (taskArgs.vars) {
		await setParentPoolCalculationVars(hre.network.name);
		await setParentPoolLiqCap(hre.network.name);
		await setLibs(hre.network.name);
		await setFeeBps(hre.network.name);
		await grantMinterRoleForLPToken(hre.network.name);
		await grantMinterRoleForIOUToken(hre.network.name);
		await setAllDstPools(hre.network.name);
	}
}

task("deploy-parent-pool", "Deploy ParentPool")
	.addFlag("proxy", "Deploy proxy")
	.addFlag("implementation", "Deploy implementation")
	.addFlag("vars", "Set contract variables")
	.addFlag("lp", "Deploy LPToken")
	.addFlag("iou", "Deploy IOU Token")
	.addOptionalParam("decimals", "Token decimals (LP, IOU)")
	.addOptionalParam("mtb", "Minimum target balance")
	.addOptionalParam("admin", "LPToken default admin")
	.addOptionalParam("minter", "LPToken minter")
	.addOptionalParam("gasoverhead", "Liquidity token gas overhead")
	.setAction(async (taskArgs, hre: HardhatRuntimeEnvironment) => {
		await deployParentPoolTask(taskArgs, hre);
	});

export { deployParentPoolTask };
