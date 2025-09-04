type DeployConfigTestnet = {
	[key: string]: {
		childPool?: {
			gasLimit: number;
		};
		proxy?: {
			gasLimit: number;
		};
	};
};

export const DEPLOY_CONFIG_TESTNET: DeployConfigTestnet = {
	inkSepolia: {
		childPool: {
			gasLimit: 1000000,
		},
		proxy: {
			gasLimit: 500000,
		},
	},
	b2Testnet: {
		childPool: {
			gasLimit: 1000000,
		},
		proxy: {
			gasLimit: 500000,
		},
	},
	seismicDevnet: {
		childPool: {
			gasLimit: 500000,
		},
		proxy: {
			gasLimit: 500000,
		},
	},
};
