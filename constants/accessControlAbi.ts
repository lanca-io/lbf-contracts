export const accessControlAbi = [
	{
		inputs: [
			{ internalType: "bytes32", name: "role", type: "bytes32" },
			{ internalType: "address", name: "account", type: "address" },
		],
		name: "grantRole",
		outputs: [],
		stateMutability: "nonpayable",
		type: "function",
	},
	{
		inputs: [
			{ internalType: "bytes32", name: "role", type: "bytes32" },
			{ internalType: "address", name: "account", type: "address" },
		],
		name: "hasRole",
		outputs: [{ internalType: "bool", name: "", type: "bool" }],
		stateMutability: "view",
		type: "function",
	},
] as const;
