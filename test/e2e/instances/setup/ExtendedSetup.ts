import { TestSetupData, Address } from "../../schemas/TestSetupSchema";

/**
 * Extended Testing Parameters Setup
 *
 * Based on ExtendedTestingParams.xlsx:
 * - ETH price: $4,000
 * - Floor price: $350M FDV → $0.35/token → 0.0000875 ETH
 * - Total supply: 1B tokens
 * - For sale: 150M tokens (15%)
 * - Total auction duration: 144,007 blocks (~20 days)
 *
 * Supply Schedule (14 steps):
 * 1. 100,800 blocks (14 days) - 0% release (wait period)
 * 2. 1 block - 33% release (3.3M MPS)
 * 3. 7,200 blocks (1 day) - 0% release
 * 4. 1 block - 5% release (500k MPS)
 * 5. 7,200 blocks (1 day) - 0% release
 * 6. 1 block - 5% release (500k MPS)
 * 7. 7,200 blocks (1 day) - 0% release
 * 8. 1 block - 10% release (1M MPS)
 * 9. 7,200 blocks (1 day) - 0% release
 * 10. 1 block - 10% release (1M MPS)
 * 11. 7,200 blocks (1 day) - 0% release
 * 12. 1 block - 10% release (1M MPS)
 * 13. 7,200 blocks (1 day) - 0% release
 * 14. 1 block - 27% release (2.7M MPS)
 *
 * Total: 144,007 blocks, 10M MPS (100%)
 * Note: The schedule is encoded in the auctionStepsData hex string below
 */
export const extendedSetup: TestSetupData = {
  name: "ExtendedSetup",
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

    groups: [
      {
        labelPrefix: "FirstGroup",
        count: 2,
        startNativeEach: "100000000000000000000000",
        startAmountEach: "100000000000000000000000",
      },
    ],
    balances: [
      {
        address: "0x1111111111111111111111111111111111111111" as Address,
        token: "0x0000000000000000000000000000000000000000",
        amount: "100000000000000000000000", // 100,000 ETH
      },
      {
        address: "0x2222222222222222222222222222222222222222" as Address,
        token: "0x0000000000000000000000000000000000000000",
        amount: "100000000000000000000000", // 100,000 ETH
      },
      {
        address: "0x3333333333333333333333333333333333333333" as Address,
        token: "0x0000000000000000000000000000000000000000",
        amount: "100000000000000000000000", // 100,000 ETH
      },
      {
        address: "0x4444444444444444444444444444444444444444" as Address,
        token: "0x0000000000000000000000000000000000000000",
        amount: "100000000000000000000000", // 100,000 ETH
      },
      {
        address: "0x5555555555555555555555555555555555555555" as Address,
        token: "0x0000000000000000000000000000000000000000",
        amount: "100000000000000000000000", // 100,000 ETH
      },
    ],
  },

  auctionParameters: {
    currency: "0x0000000000000000000000000000000000000000" as Address, // Native ETH
    auctionedToken: "ExtendedToken",
    tokensRecipient: "0x3333333333333333333333333333333333333333" as Address,
    fundsRecipient: "0x4444444444444444444444444444444444444444" as Address,
    auctionDurationBlocks: 144007, // Total duration from decoded steps data
    claimDelayBlocks: 7200, // 1 day
    tickSpacing: "69324642199981300000000", // From params - large value as string
    validationHook: "0x0000000000000000000000000000000000000000" as Address,
    floorPrice: "6932464219998130000000000", // 0.0000875 ETH in Q96 format
    // Using the exact hex string from the params file
    auctionStepsData:
      "0x00000000000189c0325aa000000000010000000000001c2007a12000000000010000000000001c2007a12000000000010000000000001c200f424000000000010000000000001c200f424000000000010000000000001c200f424000000000010000000000001c202932e00000000001",
  },

  additionalTokens: [
    {
      name: "ExtendedToken",
      decimals: "18",
      totalSupply: "1000000000000000000000000000", // 1 billion tokens (1e9 * 1e18)
      percentAuctioned: "15.0", // 15% of 1B = 150M tokens
    },
    {
      name: "USDC",
      decimals: "6",
      totalSupply: "1000000000000",
      percentAuctioned: "0.0",
    },
  ],
};
