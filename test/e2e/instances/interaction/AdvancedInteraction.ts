import { TestInteractionData, Address, AssertionInterfaceType, Side, AmountType, PriceType, ActionType } from '../../schemas/TestInteractionSchema';

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
          amount: { side: Side.INPUT, type: AmountType.RAW, value: "1000000000000000000" }, // 1 ETH
          price: { type: PriceType.RAW, value: "87150978765690771352898345369600" },
          previousTick: 1
        },
        {
          atBlock: 50,
          amount: { side: Side.INPUT, type: AmountType.RAW, value: "500000000000000000" }, // 0.5 ETH
          price: { type: PriceType.RAW, value: "90000000000000000000000000000000" },
          previousTick: 2
        }
      ]
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
    }
  ],
  assertions: [
    {
      atBlock: 100,
      reason: "Check bidder balance after complex bidding",
      assert: {
        type: AssertionInterfaceType.BALANCE,
        address: "0x1111111111111111111111111111111111111111" as Address,
        token: "0x0000000000000000000000000000000000000000" as Address,
        expected: "19997499273804168297382" // Expected ETH balance after bids and transfer (20,000 - 1.5 ETH - 1 ETH transfer - gas fees)
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
        type: AssertionInterfaceType.POOL,
        tick: "100",
        sqrtPriceX96: "79228162514264337593543950336000",
        liquidity: "1000000000000000000000"
      }
    }
  ]
};
