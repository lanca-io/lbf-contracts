import { task } from "hardhat/config";

task("test-task", "A test task").setAction(async taskArgs => {
	console.log(hre.network.name);

	console.log("Running test-script");
});

export default {};
