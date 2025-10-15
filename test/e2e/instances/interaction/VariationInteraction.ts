import { TestInteractionData, Address, AssertionInterfaceType, PriceType } from "../../schemas/TestInteractionSchema";

export const variationInteraction: TestInteractionData = {
  name: "VariationInteraction",
  namedBidders: [
    {
      address: "0x1111111111111111111111111111111111111111" as Address,
      label: "VariationBidder1",
      recurringBids: [],
      bids: [
        {
          atBlock: 15,
          // Base amount with +/- 10% variation (900M - 1.1B wei)
          amount: {
            value: "1000000000000000000", // 1 ETH base
            variation: "100000000000000000", // +/- 0.1 ETH
          },
          price: { type: PriceType.RAW, value: "87150978765690771352898345369600" },
          previousTick: 1,
        },
        {
          atBlock: 25,
          // Another bid with variation
          amount: {
            value: "500000000000000000", // 0.5 ETH base
            variation: "50000000000000000", // +/- 0.05 ETH
          },
          price: { type: PriceType.RAW, value: "90000000000000000000000000000000" },
          previousTick: 2,
        },
      ],
    },
    {
      address: "0x2222222222222222222222222222222222222222" as Address,
      label: "VariationBidder2",
      recurringBids: [],
      bids: [
        {
          atBlock: 20,
          // Bid with larger variation
          amount: {
            value: "800000000000000000", // 0.8 ETH base
            variation: "200000000000000000", // +/- 0.2 ETH
          },
          price: { type: PriceType.RAW, value: "88150978765690771352898345369600" },
          previousTick: 1,
        },
      ],
    },
  ],
  actions: [],
  assertions: [
    {
      atBlock: 30,
      reason: "Check bidder 1 balance after bids with variation",
      assert: {
        type: AssertionInterfaceType.BALANCE,
        address: "0x1111111111111111111111111111111111111111" as Address,
        token: "0x0000000000000000000000000000000000000000" as Address,
        // Expected around 3.5 ETH remaining (5 - 1 - 0.5)
        // But with variations, could be 3.35 - 3.65 ETH
        expected: "3500000000000000000",
        variance: "5%", // Allow 5% variance due to random amounts
      },
    },
    {
      atBlock: 30,
      reason: "Check bidder 2 balance after bid with larger variation",
      assert: {
        type: AssertionInterfaceType.BALANCE,
        address: "0x2222222222222222222222222222222222222222" as Address,
        token: "0x0000000000000000000000000000000000000000" as Address,
        // Expected around 4.2 ETH remaining (5 - 0.8)
        // But with large variation, could be 4.0 - 4.4 ETH
        expected: "4200000000000000000",
        variance: "10%", // Allow 10% variance due to large random variation
      },
    },
    {
      atBlock: 40,
      reason: "Check total supply remains constant despite variations",
      assert: {
        type: AssertionInterfaceType.TOTAL_SUPPLY,
        token: "VariationToken",
        expected: "1000000000000000000000", // Should always be exactly this
      },
    },
    {
      atBlock: 45,
      reason: "Check auction state with variance on currencyRaised",
      assert: {
        type: AssertionInterfaceType.AUCTION,
        isGraduated: false,
        clearingPrice: "79228162514264337593543950336000",
        // Currency raised will vary based on random bid amounts
        // Base expectation: ~2.3 ETH, but with variations could be 2.05 - 2.55 ETH
        currencyRaised: {
          amount: "2300000000000000000",
          variation: "250000000000000000", // +/- 0.25 ETH variation
        },
        latestCheckpoint: {
          clearingPrice: "79228162514264337593543950336000",
          // These will also vary, so we use VariableAmount
          currencyRaisedQ96_X7: {
            amount: "1822000000000000000000000000000000000000000000000",
            variation: "200000000000000000000000000000000000000000000000", // Allow variation
          },
          currencyRaisedAtClearingPriceQ96_X7: "0",
          cumulativeMpsPerPrice: {
            amount: "190147590034234410224505480806400",
            variation: "20000000000000000000000000000000", // Allow variation
          },
          cumulativeMps: "3000000",
          prev: "20",
          next: "18446744073709551615",
        },
      },
    },
  ],
};
