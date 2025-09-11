import { task } from "hardhat/config";

import { conceroNetworks } from "../constants";
import { grantMinterRoleForIOUToken } from "./utils/grantMinterRoleForIOUToken";
import { setAllDstPools } from "./utils/setAllDstPools";
import { setLancaKeeper } from "./utils/setLancaKeeper";

task("update-all-pools-vars").setAction(async () => {
	for (const network in conceroNetworks) {
		try {
			await setLancaKeeper(network);
			await setAllDstPools(network);
			await grantMinterRoleForIOUToken(network);
		} catch (e) {
			console.error(e);
		}
	}
});

export default {};
