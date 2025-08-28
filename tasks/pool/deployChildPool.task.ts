import { task } from "hardhat/config";

import { type HardhatRuntimeEnvironment } from "hardhat/types";

import { ProxyEnum } from "../../constants";
import { deployChildPool } from "../../deploy/ChildPool";
import { deployIOUToken } from "../../deploy/IOUToken";
import { deployProxyAdmin } from "../../deploy/ProxyAdmin";
import { deployTransparentProxy } from "../../deploy/TransparentProxy";
import { compileContracts } from "../../utils/compileContracts";
import { grantMinterRoleForIOUToken } from "../utils/grantMinterRoleForIOUToken";
import { setAllDstPools } from "../utils/setAllDstPools";
import { setDstPool } from "../utils/setDstPool";
import { setLancaKeeper } from "../utils/setLancaKeeper";
import { upgradeProxyImplementation } from "../utils/upgradeProxyImplementation";

async function deployChildPoolTask(taskArgs: any, hre: HardhatRuntimeEnvironment) {
	compileContracts({ quiet: true });

	if (taskArgs.iou) {
		await deployIOUToken(hre, { defaultAdmin: taskArgs.admin, minter: taskArgs.minter });
	}

	if (taskArgs.implementation) {
		await deployChildPool(hre);
	}

	if (taskArgs.proxy) {
		await deployProxyAdmin(hre, ProxyEnum.childPoolProxy);
		await deployTransparentProxy(hre, ProxyEnum.childPoolProxy);
		await grantMinterRoleForIOUToken(hre.network.name);
	}

	if (taskArgs.implementation) {
		await upgradeProxyImplementation(hre, ProxyEnum.childPoolProxy, false);
	}

	if (taskArgs.vars) {
		await setLancaKeeper(hre.network.name);
		await setAllDstPools(hre.network.name);
	}
}

task("deploy-child-pool", "Deploy ChildPool")
	.addFlag("proxy", "Deploy proxy")
	.addFlag("implementation", "Deploy implementation")
	.addFlag("iou", "Deploy IOU Token")
	.addFlag("vars", "Set variables")
	.setAction(async (taskArgs, hre: HardhatRuntimeEnvironment) => {
		await deployChildPoolTask(taskArgs, hre);
	});

export { deployChildPoolTask };
