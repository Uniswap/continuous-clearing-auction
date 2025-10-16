import {
  TestInteractionData,
  Address,
  PriceType,
  ActionType,
  AdminActionMethod,
  AssertionInterfaceType,
} from "../../schemas/TestInteractionSchema";

/**
 * Complex Extended interaction with extended bidding patterns
 *
 * Supply schedule: 150M tokens total
 * - Block 100,810-100,811: 33% (49.5M tokens) @ floor = ~4,331 ETH needed
 * - Block 108,011-108,012: 5% (7.5M tokens) @ floor = ~656 ETH
 * - Block 115,212-115,213: 5% (7.5M tokens) @ floor = ~656 ETH
 * - Block 122,413-122,414: 10% (15M tokens) @ floor = ~1,312 ETH
 * - Block 129,614-129,615: 10% (15M tokens) @ floor = ~1,312 ETH
 * - Block 136,815-136,816: 10% (15M tokens) @ floor = ~1,312 ETH
 * - Block 144,016-144,017: 27% (40.5M tokens) @ floor = ~3,544 ETH
 *
 * Floor price: 0.0000875 ETH (6932464219998130000000000 in Q96)
 * Tick spacing: 69324642199981300000000
 * Tick prices: floor + (n * tickSpacing) where n = 0, 1, 2, 3...
 */
export const extendedInteraction: TestInteractionData = {
  name: "ExtendedInteraction",
  namedBidders: [
    {
      address: "0x1111111111111111111111111111111111111111" as Address,
      label: "EarlyBidder",
      recurringBids: [
        {
          startBlock: 511,
          intervalBlocks: 7,
          occurrences: 10,
          amount: { value: "500000000000000000000" }, // 500 ETH at floor
          price: {
            type: PriceType.RAW,
            value: "7695035284197924300000000", // Tick 100 - floor price
          },
          prevTickPrice: "6932464219998130000000000",
        },
      ],
      bids: [
        {
          atBlock: 811, // Right after 33% release - need ~4,331 ETH for 33%
          amount: { value: "5000000000000000000000" }, // 5,000 ETH at floor
          price: {
            type: PriceType.RAW,
            value: "7695035284197924300000000", // Tick 100 - floor price
          },
          prevTickPrice: "6932464219998130000000000", // Use floor price as hint
        },
        {
          atBlock: 812, // Continued bidding
          amount: { value: "3000000000000000000000" }, // 3,000 ETH
          price: {
            type: PriceType.RAW,
            value: "7625710641997943000000000", // Tick 110 - above floor
          },
          prevTickPrice: "6932464219998130000000000",
        },
        {
          atBlock: 108012, // Right after first 5% release
          amount: { value: "5000000000000000000000" }, // 2,000 ETH at floor
          price: {
            type: PriceType.RAW,
            value: "13726279155596297400000000", // Floor price
          },
          prevTickPrice: "6932464219998130000000000",
        },
      ],
    },
    {
      address: "0x2222222222222222222222222222222222222222" as Address,
      label: "AggressiveBidder",
      recurringBids: [
        {
          startBlock: 115213, // Starting at second 5% release
          intervalBlocks: 7201, // Bid right after each release phase
          occurrences: 4, // Bid at 4 release phases (115213, 122414, 129615, 136816)
          amount: { value: "2500000000000000000000" }, // 2,500 ETH per bid = 10,000 ETH total
          price: {
            type: PriceType.RAW,
            value: "13864928439996260000000000",
          },
          priceFactor: 1.01,
          prevTickPrice: "6932464219998130000000000",
          hookData: "0x",
        },
      ],
      bids: [],
    },
    {
      address: "0x5555555555555555555555555555555555555555" as Address,
      label: "SmallRepetitiveBidder",
      recurringBids: [
        {
          startBlock: 100101,
          intervalBlocks: 2,
          occurrences: 800,
          amount: { value: "1000000000000000000" }, // 1 ETH
          price: {
            type: PriceType.RAW,
            value: "6932464219998130000000000", // Floor price
          },
          prevTickPrice: "6932464219998130000000000",
        },
      ],
      bids: [],
    },
    {
      address: "0x3333333333333333333333333333333333333333" as Address,
      label: "ConservativeBidder",
      recurringBids: [
        {
          startBlock: 100100,
          intervalBlocks: 2,
          occurrences: 800,
          amount: { value: "3000000000000000000" }, // 3 ETH
          price: {
            type: PriceType.RAW,
            value: "6932464219998130000000000", // Floor price
          },
          prevTickPrice: "6932464219998130000000000",
        },
      ],
      bids: [
        {
          atBlock: 108050, // During wait
          amount: { value: "3000000000000000000000" }, // 3,000 ETH
          price: {
            type: PriceType.RAW,
            value: "8318957063997756000000000", // Tick 120 - higher price
          },
          prevTickPrice: "6932464219998130000000000", // Hint at tick 110
        },
        {
          atBlock: 115250, // During wait
          amount: { value: "3000000000000000000000" }, // 3,000 ETH
          price: {
            type: PriceType.RAW,
            value: "9012203485997569000000000", // Tick 130
          },
          prevTickPrice: "6932464219998130000000000", // Hint at tick 120
        },
      ],
    },
    {
      address: "0x4444444444444444444444444444444444444444" as Address,
      label: "LateEntrant",
      recurringBids: [
        {
          startBlock: 130007,
          intervalBlocks: 1,
          occurrences: 902,
          amount: { value: "4000000000000000000" }, // 4 ETH
          price: {
            type: PriceType.RAW,
            value: "9705449907997382000000000", // Tick 140
          },
          prevTickPrice: "6932464219998130000000000",
        },
      ],
      bids: [
        {
          atBlock: 130000, // Mid-late auction
          amount: { value: "4000000000000000000000" }, // 4,000 ETH
          price: {
            type: PriceType.RAW,
            value: "9705449907997382000000000", // Tick 140
          },
          prevTickPrice: "6932464219998130000000000", // Hint at tick 130
        },
        {
          atBlock: 140001, // Late in auction
          amount: { value: "4000000000000000000000" }, // 4,000 ETH
          price: {
            type: PriceType.RAW,
            value: "17400485192195306300000000",
          },
          prevTickPrice: "6932464219998130000000000", // Hint at tick 140
        },
        {
          atBlock: 140002, // Late in auction
          amount: { value: "4000000000000000000000" }, // 4,000 ETH
          price: {
            type: PriceType.RAW,
            value: "17469809834395287600000000",
          },
          prevTickPrice: "6932464219998130000000000", // Hint at tick 140
        },
        {
          atBlock: 140004, // Late in auction
          amount: { value: "4000000000000000000000" }, // 4,000 ETH
          price: {
            type: PriceType.RAW,
            value: "18024406971995138000000000",
          },
          prevTickPrice: "6932464219998130000000000", // Hint at tick 140
        },
        {
          atBlock: 144016, // Final 27% release block
          amount: { value: "8000000000000000000000" }, // 8,000 ETH
          price: {
            type: PriceType.RAW,
            value: "18024406971995138000000000",
          },
          prevTickPrice: "6932464219998130000000000",
        },
      ],
    },
  ],
  actions: [
    {
      type: ActionType.ADMIN_ACTION,
      interactions: [
        [
          {
            atBlock: 144017,
            method: AdminActionMethod.CHECKPOINT,
          },
        ],
      ],
    },
  ],
  assertions: [],
};
