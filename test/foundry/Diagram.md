# Foundry Test Module Inheritance Diagram

## Inheritance Structure

```mermaid
graph TD
    A[forge-std/Test.sol] --> B[LancaTest]
    C[forge-std/Script.sol] --> D[LancaBaseScript]
    D --> B

    B --> E[ChildPoolBase]
    B --> F[ParentPoolBase]

    H --> I[ParentPoolDepositTest]

    style A fill:#e1f5fe
    style C fill:#e1f5fe
    style B fill:#f3e5f5
    style D fill:#fff3e0
    style E fill:#e8f5e8
    style F fill:#e8f5e8
    style G fill:#fff9c4
    style H fill:#fff9c4
    style I fill:#ffebee
```

## Module Descriptions

- **LancaBaseScript**: Deployment config, test addresses, constants
- **LancaTest**: Combined base with deployment + testing utilities
- **ChildPoolBase**: ChildPool setup, rebalancer utilities, deficit/surplus helpers
- **ParentPoolBase**: ParentPool setup, deposit/withdrawal queue management
- **ParentPoolDepositTest**: Concrete tests for deposit functionality

## Key Features

- Multiple inheritance pattern (LancaTest extends both Script and Test)
- Layered setUp() chain with super.setUp() calls
- Specialized utilities at each level
- Helper functions for common operations
- Event capture and queue ID tracking
