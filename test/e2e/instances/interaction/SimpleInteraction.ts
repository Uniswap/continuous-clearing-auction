import { TestInteractionData, Address, AssertionInterfaceType, Side, AmountType, PriceType } from '../../schemas/TestInteractionSchema';

export const simpleInteraction: TestInteractionData = {
  name: "SimpleInteraction",
  namedBidders: [
    {
      address: "0x1111111111111111111111111111111111111111" as Address,
      label: "SimpleBidder",
      bids: [
        {
          atBlock: 10,
          amount: { side: Side.INPUT, type: AmountType.RAW, value: "1000000000000000000" },
          price: { type: PriceType.RAW, value: "87150978765690771352898345369600" },
          previousTick: 1
        }
      ],
      recurringBids: []
    }
  ],
  
  groups: [],

  actions: [],

  assertions: [
    {
      atBlock: 20,
      reason: "Check bidder native currency balance after bid",
      assert: {
        type: AssertionInterfaceType.BALANCE,
        address: "0x1111111111111111111111111111111111111111" as Address,
        token: "0x0000000000000000000000000000000000000000" as Address,
        expected: "999564488891352473"
      }
    }
  ]
};
