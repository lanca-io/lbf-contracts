# LBF Contracts Deployment Scripts

This folder contains Hardhat deployment scripts for the Lanca Borrowing Facility (LBF) pool contracts.

## Deployment Order

The contracts must be deployed in the following order due to dependencies:

1. **LPToken** (`00_deploy_lptoken.ts`) - LP token for ParentPool
2. **IOUToken** (`01_deploy_ioutoken.ts`) - IOU token for debt tracking
3. **ParentPool** (`02_deploy_parentpool.ts`) - Main pool contract
4. **ChildPool** (`03_deploy_childpool.ts`) - Child pool contract (optional)

## Required Environment Variables

Before deploying, ensure the following environment variables are set:

```bash
# Network-specific USDC token address
USDC_{NETWORK_NAME}=0x...

# Concero Router address
CONCERO_ROUTER_{NETWORK_NAME}=0x...
```

Where `{NETWORK_NAME}` is the uppercase network name (e.g., `SEPOLIA`, `ARBITRUM`, `BASE`).

## Deployment Commands

### Deploy Individual Contracts

```bash
# Deploy only LPToken
npx hardhat deploy --tags LPToken --network <network-name>

# Deploy only IOUToken
npx hardhat deploy --tags IOUToken --network <network-name>

# Deploy only ParentPool (requires LPToken and IOUToken)
npx hardhat deploy --tags ParentPool --network <network-name>

# Deploy only ChildPool (requires IOUToken)
npx hardhat deploy --tags ChildPool --network <network-name>
```

### Deploy All Contracts

```bash
# Deploy all pool contracts in the correct order
npx hardhat deploy --tags AllPools --network <network-name>

# Or deploy all contracts with dependencies
npx hardhat deploy --network <network-name>
```

## Post-Deployment

After deployment, the scripts will:

1. Automatically save contract addresses to environment files (`.env.deployments.{networkType}`)
2. Grant necessary roles:
   - `MINTER_ROLE` on LPToken to ParentPool
   - `POOL_ROLE` on IOUToken to both ParentPool and ChildPool

## Contract Addresses

Deployed contract addresses are saved with the following environment variable names:

- `LPTOKEN_{NETWORK_NAME}` - LP Token address
- `IOUTOKEN_{NETWORK_NAME}` - IOU Token address
- `PARENT_POOL_{NETWORK_NAME}` - Parent Pool address
- `CHILD_POOL_{NETWORK_NAME}` - Child Pool address

## Customizing Deployment

You can override deployment parameters by passing custom arguments:

```typescript
import { deployParentPool } from "./deploy";

// Custom deployment with different parameters
await deployParentPool(hre, {
  liquidityToken: "0x...", // Custom USDC address
  liquidityTokenDecimals: 6,
  conceroRouter: "0x...", // Custom router address
});
```

## Network-Specific Notes

- **Mainnet**: Only ParentPool is deployed (no ChildPool)
- **Testnet/Localhost**: Both ParentPool and ChildPool are deployed
- **Chain Selector**: Automatically retrieved from network configuration

## Troubleshooting

1. **Missing Environment Variables**: Check that all required env vars are set in the appropriate `.env` files
2. **Deployment Order**: Ensure dependencies are deployed first (use tags to control order)
3. **Gas Issues**: Adjust gas settings in `hardhat.config.ts` if needed
4. **Role Permissions**: Ensure the deployer account has admin rights for role management