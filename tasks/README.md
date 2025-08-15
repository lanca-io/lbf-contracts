# Hardhat tasks best practices

1. Files containing hardhat tasks should be named fileName.task.ts.
2. Import hre only within the task block and do not pass it on to function parameters. The exception is deployment scripts where hre is passed as a parameter. If it is a task that deals with setting variables or withdrawing fees, etc., then hre.network.name must be passed.
3. Before setting storage var, always check what value it contains. If the state does not change, there is no need to call the setter.
