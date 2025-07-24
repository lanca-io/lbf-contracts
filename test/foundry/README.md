# LBF Contracts Test Suite

This directory contains the Foundry test suite for the Lanca Bridging Framework (LBF) contracts.

## Directory Structure

```
test/foundry/
├── ParentPool/          # ParentPool specific tests
│   ├── base/           # Base test contracts for ParentPool
│   └── *.t.sol         # Individual test files
├── ChildPool/          # ChildPool specific tests
│   ├── base/           # Base test contracts for ChildPool
│   └── *.t.sol         # Individual test files
├── scripts/            # Deployment and utility scripts
│   ├── deploy/         # Contract deployment scripts
│   └── *.s.sol         # Utility scripts
└── utils/              # Test utilities and base contracts
    └── LancaTest.sol   # Main test base contract
```

## Base Contracts

### LancaTest
The main test base contract that all tests inherit from. Provides common setup and utilities.

### LancaBaseScript
Base script contract containing shared variables and configuration for all scripts and tests:
- Test addresses (user, liquidityProvider, operator, lancaKeeper)
- Chain selectors and configuration
- Pool configuration constants
- Helper functions for funding and time manipulation

### ParentPoolBase / ParentPoolTest
Base contracts for ParentPool tests providing:
- ParentPool deployment and setup
- Helper functions for deposits and withdrawals
- Queue management utilities
- Child pool setup helpers
- Assertion helpers

### ChildPoolBase / ChildPoolTest
Base contracts for ChildPool tests providing:
- ChildPool deployment and setup
- Rebalancer management utilities
- Liquidity provision helpers
- Cross-chain simulation utilities
- Pool state getters

## Deployment Scripts

### DeployMockERC20
Deploys mock ERC20 tokens for testing (primarily USDC).

### DeployLPToken
Deploys the LP token used by ParentPool.

### DeployIOUToken
Deploys the IOU token used by ChildPool for tracking rebalancer debt.

### DeployParentPool
Deploys the ParentPool contract with configurable parameters.

### DeployChildPool
Deploys ChildPool contracts with support for multiple chains.

## Utility Scripts

### DisplayPoolValues
Displays current state and values of deployed pools, tokens, and system overview.

## Running Tests

### Run all tests
```bash
forge test
```

### Run specific test file
```bash
forge test --match-path test/foundry/ParentPool/Deposit.t.sol
```

### Run with verbosity
```bash
forge test -vvv
```

### Run with gas reporting
```bash
forge test --gas-report
```

## Writing New Tests

1. Create a new test file in the appropriate directory (ParentPool/ or ChildPool/)
2. Import the corresponding base test contract:
   ```solidity
   import {ParentPoolTest} from "./base/ParentPoolTest.sol";
   // or
   import {ChildPoolTest} from "./base/ChildPoolTest.sol";
   ```
3. Inherit from the base test contract
4. Override `setUp()` if additional setup is needed
5. Write test functions prefixed with `test_`

### Example Test Structure
```solidity
pragma solidity 0.8.28;

import {ParentPoolTest} from "./base/ParentPoolTest.sol";

contract MyNewTest is ParentPoolTest {
    function setUp() public override {
        super.setUp();
        // Additional setup
    }

    function test_MyFeature() public {
        // Test implementation
    }
}
```

## Environment Variables

The test suite uses the following environment variables:
- `DEPLOYER_ADDRESS`: Address used for deployments (defaults to generated address)
- `PROXY_DEPLOYER_ADDRESS`: Address for proxy deployments (defaults to generated address)
- `CONCERO_ROUTER_ADDRESS`: Address of Concero router (defaults to generated address)

## Test Helpers

### Common Helper Functions
- `fundAddress(address, uint256)`: Fund an address with ETH
- `advanceTime(uint256)`: Advance block timestamp
- `advanceBlocks(uint256)`: Advance block number
- `enterDepositQueue()`: Helper for deposits
- `enterWithdrawQueue()`: Helper for withdrawals
- `triggerDepositWithdrawProcess()`: Process queued operations
- `setupChildPools()`: Setup multiple child pools
- `getPoolBalances()`: Get system-wide balances

## Conventions

1. Use descriptive test names that explain what is being tested
2. Follow the Arrange-Act-Assert pattern
3. Use the provided assertion helpers for common checks
4. Log important values using `console.log()` for debugging
5. Group related tests in the same file
6. Use constants for repeated values
7. Mock external dependencies when needed

## Note

This test suite is designed for the LBF contracts which are currently in development. Individual feature tests should be added as the contracts mature and specific functionality is finalized.