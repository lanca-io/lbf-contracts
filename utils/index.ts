export { compileContracts } from "./compileContracts";
export { configureDotEnv } from "./configureDotEnv";
export { createViemChain } from "./createViemChain";
export { getEnvVar, getEnvAddress } from "./getEnvVar";
export { getWallet } from "./getWallet";
export {
	getClients,
	getFallbackClients,
	getTestClient,
	type ExtendedTestClient,
} from "./getViemClients";
export { localhostViemChain, hardhatViemChain } from "./localhostViemChain";
export { updateEnvVariable, updateEnvAddress } from "./updateEnvVariable";
export { default as updateEnvVariableDefault } from "./updateEnvVariable";
export { log, warn, err } from "./log";
