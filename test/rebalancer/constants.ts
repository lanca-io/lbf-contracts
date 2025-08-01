import { IOU_TOKEN_DECIMALS } from "@lanca/rebalancer/src/constants";

export const TEST_CONSTANTS = {
	// Network constants
	LOCALHOST_URL: "http://127.0.0.1:8545",
	LOCALHOST_CHAIN_ID: 1,
	LOCALHOST_CHAIN_NAME: "Localhost",

	// Token constants
	USDC_DECIMALS: 6,
	IOU_TOKEN_DECIMALS: 18,

	// Test timeouts (in milliseconds)
	DEFAULT_TIMEOUT: 120000,
	EVENT_TIMEOUT: 10000,
	BALANCE_TIMEOUT: 60000,

	// Test values
	DEFAULT_IOU_MINT_AMOUNT: "100",
	DEFAULT_USDC_MINT_AMOUNT: "100",
	DEFAULT_ETH_BALANCE: "100",
	DEFAULT_NATIVE_TRANSFER: "1",

	// Test intervals
	BLOCK_CHECK_INTERVAL: 1000,
	CHAIN_STARTUP_INTERVAL: 100,
} as const;

export const ROLE_CONSTANTS = {
	MINTER_ROLE: "MINTER_ROLE",
} as const;

export const EVENT_NAMES = {
	DEFICIT_FILLED: "DeficitFilled",
	SURPLUS_TAKEN: "SurplusTaken",
} as const;
