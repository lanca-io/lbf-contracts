import { deployChildPoolTask } from "./pool/deployChildPool.task";
import { deployParentPoolTask } from "./pool/deployParentPool.task";
import depositToParentPoolTask from "./pool/depositToParentPool.task";
import withdrawFromParentPoolTask from "./pool/withdrawFromParentPool.task";
import { setDstPoolTask } from "./setDstPool.task";
import { setLancaKeeperTask } from "./setLancaKeeper.task";
import testTask from "./testTask";
import { deployMockUSDCTask } from "./usdc/deployMockUSDC.task";

export default {
	testTask,
	deployParentPoolTask,
	deployChildPoolTask,
	deployMockUSDCTask,
	setDstPoolTask,
	setLancaKeeperTask,
	depositToParentPoolTask,
	withdrawFromParentPoolTask,
};
