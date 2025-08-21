import { deployChildPoolTask } from "./deployChildPool/deployChildPool.task";
import { deployMockUSDCTask } from "./deployMockUSDC/deployMockUSDC.task";
import { deployParentPoolTask } from "./deployParentPool/deployParentPool.task";
import { setDstPoolTask } from "./setDstPool.task";
import { setLancaKeeperTask } from "./setLancaKeeper.task";
import testTask from "./testTask";

export default {
	testTask,
	deployParentPoolTask,
	deployChildPoolTask,
	deployMockUSDCTask,
	setDstPoolTask,
	setLancaKeeperTask,
};
