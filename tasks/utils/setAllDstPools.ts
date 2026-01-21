import {
	ConceroMainnetNetworkNames,
	ConceroTestnetNetworkNames,
	conceroNetworks,
	mainnetNetworks,
	testnetNetworks,
} from "@concero/contract-utils";

import { setDstPool } from "./setDstPool";

export async function setAllDstPools(
	srcNetworkName: ConceroTestnetNetworkNames | ConceroMainnetNetworkNames,
) {
	const networks = conceroNetworks[srcNetworkName].viemChain.testnet
		? testnetNetworks
		: mainnetNetworks;

	for (const network in networks) {
		if (srcNetworkName == network) continue;
		await setDstPool(srcNetworkName, network);
	}
}
