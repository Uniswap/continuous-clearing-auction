import { TestInteractionData, Address, AssertionInterfaceType, PriceType, ActionType, AdminActionMethod } from '../../schemas/TestInteractionSchema';

export const advancedInteraction: TestInteractionData = {
  name: "AdvancedInteraction",
  namedBidders: [
    {
      address: "0x1111111111111111111111111111111111111111" as Address,
      label: "AdvancedBidder",
      recurringBids: [],
      bids: [
        {
          atBlock: 20,
          amount: {  value: "1000000000000000000" }, // 1 ETH
          price: { type: PriceType.RAW, value: "87150978765690771352898345369600" },
          previousTick: 1
        },
        {
          atBlock: 50,
          amount: {  value: "500000000000000000" }, // 0.5 ETH
          price: { type: PriceType.RAW, value: "90000000000000000000000000000000" },
          previousTick: 2
        }
      ]
    },
    {
      address: "0x3333333333333333333333333333333333333333" as Address,
      label: "RecurringBidder",
      recurringBids: [
        {
          startBlock: 55,
          intervalBlocks: 10,
          occurrences: 5,
          amount: {  value: "200000000000000000" }, // 0.2 ETH
          price: { type: PriceType.RAW, value: "88150978765690771352898345369600" },
          previousTick: 1,
          previousTickIncrement: 1,
          amountFactor: 1.0, // 0% increase each time
          priceFactor: 1.0,  // 0% increase each time
          hookData: "0x"
        }
      ],
      bids: []
    }
  ],
  actions: [
    {
      type: ActionType.TRANSFER_ACTION,
      interactions: [
        [
            {
              atBlock: 80,
              value: {
                from: "0x1111111111111111111111111111111111111111" as Address,
                to: "0x2222222222222222222222222222222222222222" as Address,
                token: "0x0000000000000000000000000000000000000000" as Address, // Native ETH
                amount: "1000000000000000000" // 1 ETH
              }
            }
        ]
      ]
    },
    {
      type: ActionType.ADMIN_ACTION,
      interactions: [
        [
          {
            atBlock: 172,
            method: AdminActionMethod.SWEEP_CURRENCY
          }
        ]
      ]
    },
    {
      type: ActionType.TRANSFER_ACTION,
      interactions: [
        [
            {
              atBlock: 200,
              value: {
                from: "0x4444444444444444444444444444444444444444" as Address,
                to: "0x2222222222222222222222222222222222222222" as Address,
                token: "USDC",
                amount: "1000000", // 1 USDC
                expectRevert: "ERC20InsufficientBalance"
              }
            }
        ]
      ]
    }
  ],
  assertions: [
    {
      atBlock: 50,
      reason: "Check event emission",
      assert: {
        type: AssertionInterfaceType.EVENT,
        eventName: "BidSubmitted",
        expectedArgs: {
          bidder: "0x1111111111111111111111111111111111111111",
          amount: "90000000000000000000000000000000"
        }
      }
    },
    {
      atBlock: 60,
      reason: "Check recurring bidder balance after first recurring bid",
      assert: {
        type: AssertionInterfaceType.BALANCE,
        address: "0x3333333333333333333333333333333333333333" as Address,
        token: "0x0000000000000000000000000000000000000000" as Address,
        expected: "9800000000000000000", // 10 - 0.2 ETH
        variance: "0.1%" // Allow some variance for gas fees
      }
    },
    {
      atBlock: 70,
      reason: "Check recurring bidder balance after multiple recurring bids",
      assert: {
        type: AssertionInterfaceType.BALANCE,
        address: "0x3333333333333333333333333333333333333333" as Address,
        token: "0x0000000000000000000000000000000000000000" as Address,
        expected: "9600000000000000000", // 10 - 0.2 ETH - 0.2 ETH
        variance: "0.5%" // Allow more variance due to multiple transactions
      }
    },
    {
      atBlock: 100,
      reason: "Check bidder balance after complex bidding",
      assert: {
        type: AssertionInterfaceType.BALANCE,
        address: "0x1111111111111111111111111111111111111111" as Address,
        token: "0x0000000000000000000000000000000000000000" as Address,
        expected: "7500000000000000000", // Expected ETH balance after bids and transfer (10 - 1.5 - 1 ETH transfer)
        variance: "0.1%" // Allow 0.01% variance due to gas fee fluctuations
      }
    },
    {
      atBlock: 120,
      reason: "Check total supply of auctioned token",
      assert: {
        type: AssertionInterfaceType.TOTAL_SUPPLY,
        token: "AdvancedToken",
        expected: "1000000000000000000000" // 1000 tokens total supply
      }
    },
    {
      atBlock: 160,
      reason: "Check auction state parameters",
      assert: {
        type: AssertionInterfaceType.AUCTION,
        isGraduated: false,
        clearingPrice: "79228162514264337593543950336000",
        currencyRaised: "1681406926406926406",
        latestCheckpoint: {
          clearingPrice: "79228162514264337593543950336000",
          totalClearedX7X7: "168140692640692640692638000000",
          cumulativeSupplySoldToClearingPriceX7X7: "0",
          cumulativeMpsPerPrice: "673439381371246869545123577856000",
          cumulativeMps: "8500000",
          prev: "85",
          next: "18446744073709551615",
        }
      }
    }
  ]
};
