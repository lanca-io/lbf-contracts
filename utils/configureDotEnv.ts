import fs from "fs";

import * as envEnc from "@chainlink/env-enc";
import * as dotenv from "dotenv";

const ENV_FILES = [
	".env",
	".env.tokens",
	".env.deployments.mainnet",
	".env.deployments.testnet",
	".env.deployments.localhost",
	".env.wallets",
];

/**
 * Configures the dotenv with paths relative to a base directory.
 * @param {string} [basePath='../../../'] - The base path where .env files are located.
 */
function configureDotEnv(basePath = "./") {
	const normalizedBasePath = basePath.endsWith("/") ? basePath : `${basePath}/`;

	ENV_FILES.forEach(file => {
		dotenv.config({ path: `${normalizedBasePath}${file}`, quiet: true });
	});

	envEnc.config({ path: process.env.PATH_TO_ENC_FILE });
}

configureDotEnv();

function reloadDotEnv(basePath = "../../") {
	const normalizedBasePath = basePath.endsWith("/") ? basePath : `${basePath}/`;

	ENV_FILES.forEach(file => {
		const fullPath = `${normalizedBasePath}${file}`;
		const currentEnv = dotenv.parse(fs.readFileSync(fullPath));

		Object.keys(currentEnv).forEach(key => {
			delete process.env[key];
		});

		dotenv.config({ path: fullPath });
	});
}

export { configureDotEnv };
