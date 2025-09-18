require("@nomicfoundation/hardhat-toolbox");

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
      chainId: 1,
      forking: {
        url: "http://localhost:8545",
        blockNumber: 20999999
      },
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
    sources: "../../src",
    tests: "./tests",
    cache: "./cache",
    artifacts: "./artifacts"
  },
  mocha: {
    timeout: 300000 // 5 minutes for complex e2e tests
  }
};
