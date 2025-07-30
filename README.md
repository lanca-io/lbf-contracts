# LBF Contracts Repository

This repository contains the smart contract implementation for the **Lanca Bridging Framework (LBF)** - a fully decentralized cross-chain liquidity infrastructure that enables seamless value transfer across blockchain networks.

## Overview

The Lanca Bridging Framework (LBF) combines a **Parent-Child Pool** model, a dynamic **IOU system**, and **hybrid liquidity management** to eliminate liquidity fragmentation, improve capital efficiency, and scale interchain operations without compromising security or decentralization.

LBF relies on **Concero V2 Messaging** as the secure transport for interchain messages and uses automated operators (**LancaKeeper**), independent participants (**Rebalancers**), and a price oracle (**ConceroPriceFeed**) to maintain efficient pool states across networks.

## Repository Structure

### Core Contracts

| Contract | Description | Location |
|----------|-------------|----------|
| **ParentPool.sol** | Primary liquidity hub that accepts LP deposits, mints LP tokens, processes batch withdrawals, and computes dynamic target balances for all Child Pools | `contracts/ParentPool/ParentPool.sol` |
| **ChildPool.sol** | Local liquidity pools on destination chains that hold funds for immediate settlement and participate in Rebalancer operations | `contracts/ChildPool/ChildPool.sol` |
| **Rebalancer.sol** | Core rebalancing mechanism enabling Rebalancers to deposit into deficit pools and withdraw from surplus pools using IOUs | `contracts/Rebalancer/Rebalancer.sol` |
| **LPToken.sol** | ERC20 token representing liquidity provider shares in the Parent Pool | `contracts/ParentPool/LPToken.sol` |
| **IOUToken.sol** | ERC20 token representing IOU claims for Rebalancer deposits, redeemable from surplus pools | `contracts/Rebalancer/IOUToken.sol` |
| **PoolBase.sol** | Base contract providing shared functionality for Parent and Child pools | `contracts/PoolBase/PoolBase.sol` |

### Supporting Infrastructure

| Contract | Description | Location |
|----------|-------------|----------|
| **LancaProxyAdmin.sol** | Proxy admin for upgradeable contracts | `contracts/Proxy/LancaProxyAdmin.sol` |
| **TransparentUpgradeableProxy.sol** | OpenZeppelin proxy implementation | `contracts/Proxy/TransparentUpgradeableProxy.sol` |
| **MockERC20.sol** | Mock ERC20 token for testing purposes | `contracts/MockERC20/MockERC20.sol` |

### Test Helpers

| Contract | Description | Location |
|----------|-------------|----------|
| **ParentPoolWrapper.sol** | Test wrapper for ParentPool with additional debugging functions | `contracts/test-helpers/ParentPoolWrapper.sol` |
| **ChildPoolWrapper.sol** | Test wrapper for ChildPool with additional debugging functions | `contracts/test-helpers/ChildPoolWrapper.sol` |

### Interfaces

| Interface | Description | Location |
|-----------|-------------|----------|
| **IParentPool.sol** | Interface for Parent Pool functionality | `contracts/ParentPool/interfaces/IParentPool.sol` |
| **ILancaKeeper.sol** | Interface for LancaKeeper integration | `contracts/ParentPool/interfaces/ILancaKeeper.sol` |
| **IRebalancer.sol** | Interface for Rebalancer operations | `contracts/Rebalancer/interfaces/IRebalancer.sol` |
| **IIOUToken.sol** | Interface for IOU token operations | `contracts/Rebalancer/interfaces/IIOUToken.sol` |
| **IPoolBase.sol** | Base interface for pool operations | `contracts/PoolBase/interfaces/IPoolBase.sol` |

## Key Features

### Unified Liquidity Layer
- LPs deposit once into the **Parent Pool** and receive fee exposure across all supported chains
- Dynamic **targetBalance** allocation adapts to network demand

### IOU Mechanism
- **Rebalancers** earn fees by correcting liquidity imbalances
- IOU tokens provide flexible redemption from surplus pools
- Protects operational liquidity through redemption constraints

### Hybrid Liquidity Management
- Combines automated planning (Parent Pool) with market-driven responsiveness (Rebalancers)
- Minimizes idle capital while maintaining fast settlement

### Security Model
- Multi-layer security with cryptographic, economic, and operational monitoring
- Strict privilege controls for critical operations
- Message integrity validation for cross-chain communication

## Architecture Components

### System Roles
- **Liquidity Providers (LPs)**: Deposit assets into Parent Pool to earn fees
- **Rebalancers**: Independent actors providing liquidity rebalancing services
- **LancaKeeper**: Automated operator managing periodic operations

### Core Flows
1. **LP Deposit**: Assets → Parent Pool → LP tokens minted
2. **Cross-Chain Transfer**: Initiated via LancaBridge contracts
3. **Rebalancer Operations**: Deposit to deficit pools, withdraw from surplus pools
4. **LP Withdrawal**: Burn LP tokens → receive underlying assets

## Development

### Prerequisites
- Node.js (v22+)
- Yarn as package manager
- Foundry (for testing)

### Setup
```bash
# Install dependencies
yarn install

# Compile contracts
yarn compile

# Run tests
yarn test

# Run Foundry tests
forge test
```

### Deployment
The project uses Hardhat for deployment with scripts located in the `deploy/` directory:
- `00_deploy_lptoken.ts` - Deploy LP Token
- `01_deploy_ioutoken.ts` - Deploy IOU Token
- `02_deploy_parentpool.ts` - Deploy Parent Pool
- `03_deploy_childpool.ts` - Deploy Child Pool
- `04_deploy_all_pools.ts` - Deploy all pools

## Testing

The project includes comprehensive test suites:
- **Hardhat tests**: Located in `test/rebalancer/`
- **Foundry tests**: Located in `test/foundry/`
- **Test helpers**: Contract wrappers for enhanced testing capabilities

## Documentation

For detailed architecture information, see:
- **[LBF Architecture Documentation](https://docs.lanca.io/lbf/architecture)** - Complete technical overview of the LBF system
- **[LBF Whitepaper](https://concero.io/lanca_whitepaper.pdf)** - Comprehensive whitepaper covering the protocol design and economics

## Security

This repository follows security best practices:
- Upgradeable contracts using OpenZeppelin proxies
- Comprehensive test coverage
- Access control mechanisms
- Economic security models
- Cross-chain message validation

---

*This repository is part of the Lanca Bridging Framework ecosystem. For questions or contributions, please refer to the project's contribution guidelines.*
