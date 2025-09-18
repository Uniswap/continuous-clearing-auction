import { TestSetupData } from '../../schemas/TestSetupSchema';

export const simpleSetup: TestSetupData = {
  env: {
    chainId: 31337,
    startBlock: "1",
    blockTimeSec: 12,
    blockGasLimit: "30000000",
    txGasLimit: "30000000",
    baseFeePerGasWei: "0",
    fork: {
      rpcUrl: "http://localhost:8545",
      blockNumber: "20999999"
    },
    balances: [
      { 
        address: "0x1111111111111111111111111111111111111111", 
        token: "0x0000000000000000000000000000000000000000", 
        amount: "2000000000000000000" 
      }
    ]
  },

  auctionParameters: {
    currency: "0x0000000000000000000000000000000000000000",
    auctionedToken: "SimpleToken",
    tokensRecipient: "0x2222222222222222222222222222222222222222",
    fundsRecipient: "0x3333333333333333333333333333333333333333",
    startOffsetBlocks: 0,
    auctionDurationBlocks: 50,
    claimDelayBlocks: 10,
    graduationThresholdMps: "1000",
    tickSpacing: 100,
    validationHook: "0x0000000000000000000000000000000000000000",
    floorPrice: "79228162514264337593543950336000"
  },

  additionalTokens: [
    {
      name: "SimpleToken",
      decimals: "18",
      totalSupply: "1000000000000000000000",
      percentAuctioned: "10.0"
    },
    {
      name: "USDC",
      decimals: "6",
      totalSupply: "1000000000000",
      percentAuctioned: "0.0"
    }
  ]
};
