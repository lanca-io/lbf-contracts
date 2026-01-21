import { conceroNetworks } from "@concero/contract-utils";

import { DEPLOY_CONFIG_TESTNET } from "./deployConfigTestnet";
import {
	ADDRESS_ZERO,
	ADMIN_SLOT,
	EMPTY_BYTES,
	ProxyEnum,
	defaultLiquidityTokenGasOverhead,
	getViemReceiptConfig,
	liqTokenDecimals,
	viemReceiptConfig,
	writeContractConfig,
} from "./deploymentVariables";
import { envPrefixes } from "./envPrefixes";
import { lancaProxyAbi } from "./lancaProxyAbi";

export {
	conceroNetworks,
	viemReceiptConfig,
	writeContractConfig,
	ProxyEnum,
	envPrefixes,
	getViemReceiptConfig,
	liqTokenDecimals,
	lancaProxyAbi,
	defaultLiquidityTokenGasOverhead,
	ADDRESS_ZERO,
	EMPTY_BYTES,
	ADMIN_SLOT,
	DEPLOY_CONFIG_TESTNET,
};
