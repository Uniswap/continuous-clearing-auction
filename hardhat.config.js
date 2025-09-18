require("@nomicfoundation/hardhat-foundry");
require("@nomicfoundation/hardhat-ethers");
require("ts-node/register");

/** @type import('hardhat/config').HardhatUserConfig */
module.exports = {
  solidity: {
    version: "0.8.26",
    settings: {
      optimizer: {
        enabled: true,
        runs: 200
      },
      viaIR: true // Required for complex contracts
    }
  },
  networks: {
    hardhat: {
      accounts: {
        count: 20,
        initialIndex: 0,
        mnemonic: "test test test test test test test test test test test junk",
        path: "m/44'/60'/0'/0",
        accountsBalance: "10000000000000000000000" // 10k ETH
      }
    }
  },
  paths: {
    sources: "./src",
    tests: "./test/e2e/tests",
    cache: "./test/e2e/cache",
    artifacts: "./test/e2e/artifacts"
  },
  mocha: {
    timeout: 300000 // 5 minutes for complex e2e tests
  },
  typechain: {
    outDir: "typechain-types",
    target: "ethers-v6"
  }
};
