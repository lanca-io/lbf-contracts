import { deployChildPoolTask } from "./deployChildPool";
import { deployParentPoolTask } from "./deployParentPool/deployParentPool.task";
import { setDstPoolTask } from "./deployParentPool/setDstPool.task";
import testTask from "./testTask";

export default {
	testTask,
	deployParentPoolTask,
	deployChildPoolTask,
	setDstPoolTask,
};
