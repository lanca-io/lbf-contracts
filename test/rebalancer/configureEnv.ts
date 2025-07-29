import dotenv from "dotenv";

dotenv.config({ path: "./test/rebalancer/.env.rebalancer" });
require("hardhat");

process.env.TENDERLY_AUTOMATIC_VERIFICATION = "false"; // Force Tenderly verification to false
