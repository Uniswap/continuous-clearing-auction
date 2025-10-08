// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

enum AuctionParametersSpace {
    TotalSupplySpace,
    FloorPriceSpace,
    TickSpacingSpace,
    ValidationHookSpace,
    TokensRecipientSpace,
    FundsRecipientSpace
}

enum AuctionPhaseSpace {
    NotYetStarted,
    FirstBlock,
    Early,
    Middle,
    LastBlock,
    Ended
}

enum TotalSupplySpace {
    Low,
    High
}

enum TokenDecimalsSpace {
    Low,
    High,
    Standard
}

enum CurrencyTypeSpace {
    Native,
    ERC20
}

enum CurrencyDecimalsSpace {
    Low,
    High,
    Standard
}

enum CurrencyAmountSpace {
    Low,
    High,
    Standard
}

enum FloorPriceSpace {
    Zero,
    OneWei,
    VeryHigh,
    VeryLow,
    AtMaxSqrtPrice
}

enum TickSpacingSpace {
    Zero,
    OneWei,
    OneBasisPoint,
    LessThanFloorPrice,
    EqualToFloorPrice,
    BiggerThanFloorPrice,
    Max
}

enum GraduatedSpace {
    No,
    Yes
}

enum SubscriptionStatusSpace {
    NotSubscribed,
    SmallSubscription,
    AlmostSubscribed,
    ExactlySubscribed,
    BarelyOversubscribed,
    MassivelyOversubscribed
}

enum ExistingBidsSpace {
    None,
    One,
    Multiple,
    Many
}

enum BidSizeSpace {
    Zero,
    OneWei,
    BidMinimum,
    Small,
    Medium,
    Large,
    Huge
}

enum BidPriceSpace {
    Zero,
    OneWei,
    AtClearingPrice,
    OneTickAboveClearing,
    ManyTicksAboveClearing,
    Max
}

enum RemainingSupplySpace {
    None,
    All
}

enum ActionSpace {
    SubmitBid,
    SubmitBidWithHint,
    ExitBid,
    ClaimTokens,
    Checkpoint
}

enum EmissionRateSpace {
    Zero,
    Small,
    Normal,
    Max
}

enum EmissionDurationSpace {
    SingleBlock,
    Short,
    Normal,
    Long
}

enum NumberOfStepsSpace {
    Zero,
    Small,
    Normal,
    Max
}

enum SenderSpace {
    NewBidder,
    RepeatBidder
}

enum ValidationHookSpace {
    None,
    Reverting,
    RevertingWithCustomError,
    OutOfGas,
    Passing
}

enum TokensRecipientSpace {
    None,
    EOA,
    Contract
}

enum FundsRecipientSpace {
    None,
    EOA,
    Contract
}
