import { defineChain } from "viem";

import { TEST_CONSTANTS } from "../constants";

export const localhostViemChain = /*#__PURE__*/ defineChain({
	id: TEST_CONSTANTS.LOCALHOST_CHAIN_ID,
	name: TEST_CONSTANTS.LOCALHOST_CHAIN_NAME,
	nativeCurrency: TEST_CONSTANTS.NATIVE_CURRENCY,
	rpcUrls: {
		default: { http: [TEST_CONSTANTS.LOCALHOST_URL] },
	},
});
