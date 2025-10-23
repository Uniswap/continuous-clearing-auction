import { TestSetupData, Address } from "../../schemas/TestSetupSchema";

export const advancedSetup: TestSetupData = {
  name: "AdvancedSetup",
  env: {
    chainId: 31337,
    startBlock: "10",
    blockTimeSec: 12,
    blockGasLimit: "100000000",
    txGasLimit: "30000000",
    baseFeePerGasWei: "0",
    fork: {
      rpcUrl: "http://localhost:8545",
      blockNumber: "1",
    },
    balances: [
      {
        address: "0x1111111111111111111111111111111111111111" as Address,
        token: "0x0000000000000000000000000000000000000000",
        amount: "10000000000000000000", // 10 ETH for complex operations
      },
      {
        address: "0x2222222222222222222222222222222222222222" as Address,
        token: "0x0000000000000000000000000000000000000000",
        amount: "1000000000000000000", // 1 ETH
      },
      {
        address: "0x3333333333333333333333333333333333333333" as Address,
        token: "0x0000000000000000000000000000000000000000",
        amount: "10000000000000000000", // 10 ETH
      },
      {
        address: "0x4444444444444444444444444444444444444444" as Address,
        token: "0x0000000000000000000000000000000000000000",
        amount: "1000000000000000000", // 1 ETH
      },
    ],
  },
  auctionParameters: {
    currency: "0x0000000000000000000000000000000000000000" as Address,
    auctionedToken: "AdvancedToken",
    tokensRecipient: "0x3333333333333333333333333333333333333333" as Address,
    fundsRecipient: "0x4444444444444444444444444444444444444444" as Address,
    auctionDurationBlocks: 100,
    claimDelayBlocks: 20,
    tickSpacing: "396140812571321687967719751680",
    validationHook: "0x0000000000000000000000000000000000000000" as Address,
    floorPrice: "79228162514264337593543950336000",
    requiredCurrencyRaised: "0",
  },
  additionalTokens: [
    {
      name: "AdvancedToken",
      decimals: "18",
      totalSupply: "1000000000000000000000", // 1000 tokens
      percentAuctioned: "20.0", // 20% of supply auctioned
    },
    {
      name: "USDC",
      decimals: "6",
      totalSupply: "1000000000000",
      percentAuctioned: "0.0",
    },
  ],
};
