import { task } from "hardhat/config";

import { type HardhatRuntimeEnvironment } from "hardhat/types";

import { ProxyEnum } from "../../constants";
import { deployIOUToken } from "../../deploy/IOUToken";
import { deployLPToken } from "../../deploy/LPToken";
import { deployParentPool } from "../../deploy/ParentPool";
import { deployProxyAdmin } from "../../deploy/ProxyAdmin";
import { deployTransparentProxy } from "../../deploy/TransparentProxy";
import { compileContracts } from "../../utils/compileContracts";
import { grantMinterRoleForIOUToken } from "../utils/grantMinterRoleForIOUToken";
import { grantMinterRoleForLPToken } from "../utils/grantMinterRoleForLPToken";
import { setLancaKeeper } from "../utils/setLancaKeeper";
import { setParentPoolVariables } from "../utils/setParentPoolVariables";
import { upgradeProxyImplementation } from "../utils/upgradeProxyImplementation";

async function deployParentPoolTask(taskArgs: any, hre: HardhatRuntimeEnvironment) {
	compileContracts({ quiet: true });

	if (taskArgs.lp) {
		await deployLPToken(hre, { defaultAdmin: taskArgs.admin, minter: taskArgs.minter });
	}

	if (taskArgs.iou) {
		await deployIOUToken(hre, { defaultAdmin: taskArgs.admin, minter: taskArgs.minter });
	}

	if (taskArgs.implementation) {
		await deployParentPool(hre, {
			liquidityTokenDecimals: taskArgs.decimals,
			minTargetBalance: taskArgs.mtb,
		});
	}

	if (taskArgs.proxy) {
		await deployProxyAdmin(hre, ProxyEnum.parentPoolProxy);
		await deployTransparentProxy(hre, ProxyEnum.parentPoolProxy);
		await grantMinterRoleForLPToken(hre.network.name);
		await grantMinterRoleForIOUToken(hre.network.name);
		await setLancaKeeper(hre.network.name);
	}

	if (taskArgs.implementation) {
		await upgradeProxyImplementation(hre, ProxyEnum.parentPoolProxy, false);
	}

	if (taskArgs.vars) {
		await setParentPoolVariables(hre.network.name);
	}
}

task("deploy-parent-pool", "Deploy ParentPool")
	.addFlag("proxy", "Deploy proxy")
	.addFlag("implementation", "Deploy implementation")
	.addFlag("vars", "Set contract variables")
	.addFlag("lp", "Deploy LPToken")
	.addFlag("iou", "Deploy IOU Token")
	.addOptionalParam("decimals", "Liquidity token decimals")
	.addOptionalParam("mtb", "Minimum target balance")
	.addOptionalParam("admin", "LPToken default admin")
	.addOptionalParam("minter", "LPToken minter")
	.setAction(async (taskArgs, hre: HardhatRuntimeEnvironment) => {
		await deployParentPoolTask(taskArgs, hre);
	});

export { deployParentPoolTask };
