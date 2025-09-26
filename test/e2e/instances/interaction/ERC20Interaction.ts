import { TestInteractionData, Address, AssertionInterfaceType, Side, AmountType, PriceType } from '../../schemas/TestInteractionSchema';

export const erc20Interaction: TestInteractionData = {
  name: "ERC20Interaction",
  namedBidders: [
    {
      address: "0x1111111111111111111111111111111111111111" as Address,
      label: "ERC20Bidder",
      bids: [
        {
          atBlock: 20,
          amount: { side: Side.INPUT, type: AmountType.RAW, value: "1000000000" }, // 1000 USDC (6 decimals)
          price: { type: PriceType.RAW, value: "87150978765690771352898345369600" },
          previousTick: 1
        }
      ],
      recurringBids: []
    }
  ],
  assertions: [
    {
      atBlock: 70,
      reason: "Check bidder USDC balance after bid",
      assert: {
        type: AssertionInterfaceType.BALANCE,
        address: "0x1111111111111111111111111111111111111111" as Address,
        token: "USDC",
        expected: "999000000000" // Expected USDC balance after bid (1M - 1K = 999K USDC)
      }
    }
  ]
};
