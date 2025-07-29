/*
hardhat compile
  --concurrency         Number of compilation jobs executed in parallel. Defaults to the number of CPU cores - 1 (default: 9)
  --force               Force compilation ignoring cache
  --no-size-contracts   Don't size contracts after running this task, even if runOnCompile option is enabled
  --no-typechain        Skip Typechain compilation
  --quiet               Makes the compilation process less verbose
 */
import { exec as execCallback, execSync } from "child_process";
import { promisify } from "util";

const exec = promisify(execCallback);

interface HardhatCompileParams {
	concurrency?: number;
	force?: boolean;
	noSizeContracts?: boolean;
	noTypechain?: boolean;
	quiet?: boolean;
}

export function compileContracts({ quiet = true, force = false }: HardhatCompileParams) {
	const packageManager = process.env["PACKAGE_MANAGER"] || "yarn";
	const command = `${packageManager} compile`;
	const args = [];
	// if (concurrency) args.push(`--concurrency ${concurrency}`);
	// if (noSizeContracts) args.push("--no-size-contracts");
	// if (noTypechain) args.push("--no-typechain");
	if (quiet) args.push("--quiet");
	if (force) args.push("--force");
	execSync(`${command} ${args.join(" ")}`, { stdio: "inherit" });
}

export async function compileContractsAsync({
	quiet = true,
	force = false,
}: HardhatCompileParams): Promise<void> {
	const packageManager = process.env["PACKAGE_MANAGER"] || "yarn";
	const command = `${packageManager} compile`;
	const args = [];
	if (quiet) args.push("--quiet");
	if (force) args.push("--force");

	const { stdout, stderr } = await exec(`${command} ${args.join(" ")}`);
	if (!quiet) {
		console.log(stdout);
		if (stderr) console.error(stderr);
	}
}
