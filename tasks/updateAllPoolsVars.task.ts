import { task } from "hardhat/config";

import { conceroNetworks } from "../constants";
import { grantMinterRoleForIOUToken } from "./utils/grantMinterRoleForIOUToken";
import { setAllDstPools } from "./utils/setAllDstPools";
import { setFeeBps } from "./utils/setFeeBps";
import { setLibs } from "./utils/setLibs";

task("update-all-pools-vars").setAction(async () => {
	for (const network in conceroNetworks) {
		if (network === "localhost" || network === "hardhat") continue;
		try {
			await setLibs(network);
			await setFeeBps(network);
			await grantMinterRoleForIOUToken(network);
			await setAllDstPools(network);
		} catch (e) {
			console.error(e);
		}
	}
});

export default {};
