import { deployChildPoolTask } from "./deployChildPool/deployChildPool.task";
import { deployParentPoolTask } from "./deployParentPool/deployParentPool.task";
import { setDstPoolTask } from "./setDstPool.task";
import testTask from "./testTask";

export default {
	testTask,
	deployParentPoolTask,
	deployChildPoolTask,
	setDstPoolTask,
};
