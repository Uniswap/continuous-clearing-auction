import { TestSetupData, Address } from "../../schemas/TestSetupSchema";

export const erc20Setup: TestSetupData = {
  name: "ERC20Setup",
  env: {
    chainId: 31337,
    startBlock: "10",
    blockTimeSec: 12,
    blockGasLimit: "30000000",
    txGasLimit: "30000000",
    baseFeePerGasWei: "0",
    fork: {
      rpcUrl: "http://localhost:8545",
      blockNumber: "1",
    },
    balances: [
      {
        address: "0x1111111111111111111111111111111111111111" as Address,
        token: "0x0000000000000000000000000000000000000000", // Native ETH for gas
        amount: "2000000000000000000", // 2 ETH for gas fees
      },
      {
        address: "0x1111111111111111111111111111111111111111" as Address,
        token: "USDC",
        amount: "1000000000000", // 1M USDC (6 decimals)
      },
    ],
  },

  auctionParameters: {
    currency: "USDC", // Use USDC as currency instead of native ETH
    auctionedToken: "SimpleToken",
    tokensRecipient: "0x2222222222222222222222222222222222222222" as Address,
    fundsRecipient: "0x3333333333333333333333333333333333333333" as Address,
    auctionDurationBlocks: 50,
    claimDelayBlocks: 10,
    tickSpacing: 100,
    validationHook: "0x0000000000000000000000000000000000000000" as Address,
    floorPrice: "79228162514264337593543950336000",
  },

  additionalTokens: [
    {
      name: "SimpleToken",
      decimals: "18",
      totalSupply: "1000000000000000000000",
      percentAuctioned: "10.0",
    },
    {
      name: "USDC",
      decimals: "6",
      totalSupply: "1000000000000",
      percentAuctioned: "0.0",
    },
  ],
};
