// hardhat.config.ts
import "@nomicfoundation/hardhat-foundry";
import "@nomicfoundation/hardhat-ethers";
import "@typechain/hardhat";

import type { HardhatUserConfig } from "hardhat/config";
import { subtask } from "hardhat/config";
import { TASK_COMPILE_SOLIDITY_GET_SOURCE_PATHS } from "hardhat/builtin-tasks/task-names";
import path from "node:path";
import * as glob from "glob";

subtask(TASK_COMPILE_SOLIDITY_GET_SOURCE_PATHS, async (_, { config }) => {
    const root = config.paths.root;
    const contractSources = glob.sync(path.join(root, "src/**/*.sol"));
    const testUtilsSources = glob.sync(path.join(root, "test/utils/**/*.sol"));
    return [...contractSources, ...testUtilsSources].map(p => path.normalize(p));
  });

const config: HardhatUserConfig = {
  solidity: {
    version: "0.8.26",
    settings: {
      optimizer: { enabled: true, runs: 200 },
      viaIR: true, // Required for complex contracts
    },
  },
  networks: {
    hardhat: {
      accounts: {
        count: 20,
        initialIndex: 0,
        mnemonic: "test test test test test test test test test test test junk",
        path: "m/44'/60'/0'/0",
        accountsBalance: "10000000000000000000000", // 10k ETH
      },
    },
  },
  paths: {
    sources: "./src",
    tests: "./test/e2e/tests",
    cache: "./test/e2e/cache",
    artifacts: "./test/e2e/artifacts",
  },
  mocha: {
    timeout: 300000, // 5 minutes for complex e2e tests
  },
  typechain: {
    outDir: "typechain-types",
    target: "ethers-v6",
    alwaysGenerateOverloads: false,
    externalArtifacts: ["out/Auction.sol/Auction.json", "out/AuctionFactory.sol/AuctionFactory.json", "out/WorkingCustomMockToken.sol/WorkingCustomMockToken.json"], // Specific Foundry artifacts
    dontOverrideCompile: false, // Let it compile if needed
  },
};

export default config;
