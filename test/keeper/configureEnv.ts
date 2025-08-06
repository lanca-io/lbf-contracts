import dotenv from "dotenv";

dotenv.config({ path: "./test/keeper/.env.keeper" });
require("hardhat");

const TENDERLY_VERIFICATION_DISABLED = "false";
process.env.TENDERLY_AUTOMATIC_VERIFICATION = TENDERLY_VERIFICATION_DISABLED; // Force Tenderly verification to false
