import { ConceroNetworkNames } from "../types/ConceroNetwork";

const networkColors: Record<ConceroNetworkNames, string> = {
	ethereum: "\x1b[30m", // grey
	arbitrum: "\x1b[34m", // blue
	polygon: "\x1b[35m", // magenta
	avalanche: "\x1b[31m", // red
	base: "\x1b[36m", // cyan
	ethereumSepolia: "\x1b[30m", // grey
	arbitrumSepolia: "\x1b[34m", // blue
	optimismSepolia: "\x1b[31m", // red
	polygonAmoy: "\x1b[35m", // magenta
	avalancheFuji: "\x1b[31m", // red
	baseSepolia: "\x1b[36m", // cyan
	hardhat: "\x1b[32m", // green
	localhost: "\x1b[32m", // green
};
const reset = "\x1b[0m";

export function log(message: any, functionName: string, networkName?: ConceroNetworkNames) {
	const greenFill = "\x1b[32m";
	const network = networkName ? `\x1b[35m[${networkName}]${reset}` : "";

	console.log(`${network}${greenFill}[${functionName}]${reset}`, message);
}

export function warn(message: any, functionName: string) {
	const yellowFill = "\x1b[33m";

	console.log(`${yellowFill}[${functionName}]${reset}`, message);
}

export function err(message: any, functionName: string, networkName?: ConceroNetworkNames) {
	const redFill = "\x1b[31m";
	const network = networkName ? `${networkColors[networkName]}[${networkName}]${reset}` : "";

	console.log(`${network}${redFill}[${functionName}] ERROR:${reset}`, message);
}

export default log;
