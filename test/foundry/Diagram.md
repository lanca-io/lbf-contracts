# Foundry Test Module Inheritance Diagram

## Inheritance Structure

```mermaid
graph TD
    A[forge-std/Test.sol] --> B[LancaTest]
    C[forge-std/Script.sol] --> D[LancaBaseScript]
    D --> B

    B --> E[ChildPoolBase]
    B --> F[ParentPoolBase]

    F --> I[ParentPoolDepositTest]

    style A fill:#e1f5fe
    style C fill:#e1f5fe
    style B fill:#f3e5f5
    style D fill:#fff3e0
    style E fill:#e8f5e8
    style F fill:#e8f5e8
    style I fill:#ffebee
```

## Module Descriptions

- **LancaBaseScript**: Deployment config, test addresses, constants
- **LancaTest**: Combined base with deployment + testing utilities
- **ChildPoolBase**: ChildPool setup, rebalancer utilities, deficit/surplus helpers
- **ParentPoolBase**: ParentPool setup, deposit/withdrawal queue management
- **ParentPoolDepositTest**: Concrete tests for deposit functionality

## Usage
```bash
make test args="-vvvvv"
```
