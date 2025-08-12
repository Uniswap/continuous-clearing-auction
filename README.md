# TWAP Auction

This repository contains the smart contracts for a TWAP (Time-Weighted Average Price) auction mechanism.

## Installation

```bash
forge install
```

## Testing

```bash
forge test
```

### Architecture

```mermaid
graph TD;
    subgraph Contracts
        AuctionFactory;
        Auction;
        AuctionStepStorage;
        TickStorage;
        CheckpointStorage;
        BidStorage;
        PermitSingleForwarder;
    end

    subgraph Libraries
        AuctionStepLib;
        BidLib;
        CheckpointLib;
        DemandLib;
        TickLib;
        CurrencyLibrary;
        SSTORE2[solady/utils/SSTORE2];
        FixedPointMathLib[solady/utils/FixedPointMathLib];
        SafeTransferLib[solady/utils/SafeTransferLib];
    end

    subgraph Interfaces
        IAuction;
        IAuctionStepStorage;
        ITickStorage;
        IPermitSingleForwarder;
        IValidationHook;
        IDistributionContract;
        IDistributionStrategy;
        IERC20Minimal;
        IAllowanceTransfer[permit2/IAllowanceTransfer];
    end

    AuctionFactory -- creates --> Auction;
    AuctionFactory -- implements --> IDistributionStrategy;

    Auction -- inherits from --> BidStorage;
    Auction -- inherits from --> CheckpointStorage;
    Auction -- inherits from --> AuctionStepStorage;
    Auction -- inherits from --> PermitSingleForwarder;
    Auction -- implements --> IAuction;

    CheckpointStorage -- inherits from --> TickStorage;
    CheckpointStorage -- uses --> CheckpointLib;
    CheckpointStorage -- uses --> BidLib;
    CheckpointStorage -- uses --> TickLib;

    Auction -- uses --> AuctionStepLib;
    Auction -- uses --> BidLib;
    Auction -- uses --> CheckpointLib;
    Auction -- uses --> DemandLib;
    Auction -- uses --> TickLib;
    Auction -- uses --> CurrencyLibrary;
    Auction -- uses --> FixedPointMathLib;
    Auction -- uses --> SafeTransferLib;

    Auction -- interacts with --> IValidationHook;
    Auction -- interacts with --> IDistributionContract;
    Auction -- interacts with --> IERC20Minimal;
    Auction -- interacts with --> IAllowanceTransfer;

    AuctionStepStorage -- uses --> AuctionStepLib;
    AuctionStepStorage -- uses --> SSTORE2;
    AuctionStepStorage -- implements --> IAuctionStepStorage;

    TickStorage -- uses --> TickLib;
    TickStorage -- uses --> DemandLib;
    TickStorage -- implements --> ITickStorage;

    BidStorage -- uses --> BidLib;

    PermitSingleForwarder -- implements --> IPermitSingleForwarder;
    PermitSingleForwarder -- interacts with --> IAllowanceTransfer;
```

### Contract Inheritance for Auction.sol

```mermaid
classDiagram
    class BidStorage
    class CheckpointStorage
    class TickStorage
    class AuctionStepStorage
    class PermitSingleForwarder
    class IAuction
    
    CheckpointStorage --|> TickStorage
    Auction --|> BidStorage
    Auction --|> CheckpointStorage
    Auction --|> AuctionStepStorage
    Auction --|> PermitSingleForwarder
    Auction --|> IAuction
    
    class Auction {
        +Demand sumDemandAboveClearing
        +checkpoint() Checkpoint
        +submitBid() uint256
        +withdrawBid() void
        +withdrawPartiallyFilledBid() void
        +claimTokens() void
    }
    
    class BidStorage {
        +uint256 nextBidId
        +_createBid() uint256
        +_getBid() Bid
        +_updateBid() void
        +_deleteBid() void
    }
    
    class CheckpointStorage {
        +uint256 floorPrice
        +uint256 lastCheckpointedBlock
        +latestCheckpoint() Checkpoint
        +clearingPrice() uint256
        +_accountFullyFilledCheckpoints() uint256, uint24
        +_accountPartiallyFilledCheckpoints() uint256, uint24, uint256
    }
```

### Auction Construction Flow

```mermaid
sequenceDiagram
    participant User
    participant AuctionFactory
    participant Auction
    participant AuctionParameters

    User->>AuctionFactory: initializeDistribution(token, amount, configData)
    AuctionFactory->>AuctionParameters: abi.decode(configData)
    AuctionFactory->>Auction: new Auction(token, amount, parameters)
    create participant NewAuction
    Auction->>NewAuction: constructor()
    NewAuction-->>Auction: address
    Auction-->>AuctionFactory: auctionContractAddress
    AuctionFactory-->>User: auctionContractAddress
```

### Bid Submission Flow

```mermaid
sequenceDiagram
    participant User
    participant Auction
    participant CheckpointStorage
    participant BidStorage
    participant TickStorage
    participant IValidationHook
    participant IAllowanceTransfer

    User->>Auction: submitBid(maxPrice, exactIn, amount, owner, prevHintId, hookData)
    alt ERC20 Token
        Auction->>IAllowanceTransfer: permit2TransferFrom(...)
    else ETH
        User-->>Auction: sends ETH with call
    end
    Auction->>Auction: _submitBid(...)
    Note over Auction: First bid in block triggers checkpoint
    alt First bid in block
        Auction->>CheckpointStorage: checkpoint()
        CheckpointStorage->>CheckpointStorage: _advanceToCurrentStep()
        CheckpointStorage->>CheckpointStorage: _calculateNewClearingPrice()
        CheckpointStorage->>CheckpointStorage: _updateCheckpoint()
        CheckpointStorage->>CheckpointStorage: _insertCheckpoint()
    end
    Auction->>TickStorage: _initializeTickIfNeeded(...)
    alt Validation hook exists
        Auction->>IValidationHook: validate(...)
    end
    Auction->>TickStorage: _updateTickAndTickUpper(...)
    Auction->>BidStorage: _createBid(...)
    BidStorage-->>Auction: bidId
    Auction->>Auction: Update sumDemandAboveClearing
    Auction-->>User: bidId
```

### Bid Withdrawal Flow

```mermaid
sequenceDiagram
    participant User
    participant Auction
    participant CheckpointStorage
    participant BidStorage
    participant TickStorage

    User->>Auction: withdrawBid(bidId) OR withdrawPartiallyFilledBid(bidId, outbidCheckpointBlock)
    Auction->>BidStorage: _getBid(bidId)
    BidStorage-->>Auction: bid
    Auction->>TickStorage: Get tick data
    TickStorage-->>Auction: tick
    
    alt Bid above clearing price (fully unfilled)
        Auction->>CheckpointStorage: _getFinalCheckpoint()
        Auction->>CheckpointStorage: _accountFullyFilledCheckpoints()
    else Bid at/below clearing price (partially filled)
        Auction->>CheckpointStorage: _getCheckpoint(outbidCheckpointBlock)
        alt Bid outbid during auction
            Auction->>CheckpointStorage: _accountPartiallyFilledCheckpoints()
            Auction->>CheckpointStorage: _accountFullyFilledCheckpoints()
        else Bid at final clearing price
            Auction->>CheckpointStorage: _accountFullyFilledCheckpoints()
            Auction->>CheckpointStorage: _accountPartiallyFilledCheckpoints()
        end
    end
    
    CheckpointStorage-->>Auction: tokensFilled, cumulativeMpsDelta
    Auction->>Auction: calculateRefund()
    Auction->>Auction: _processBidWithdraw()
    Auction->>BidStorage: _updateBid() OR _deleteBid()
    Auction->>Auction: currency.transfer(refund)
    Auction-->>User: Bid withdrawn
```

### Token Claiming Flow

```mermaid
sequenceDiagram
    participant User
    participant Auction
    participant BidStorage
    participant Token

    User->>Auction: claimTokens(bidId)
    Auction->>BidStorage: _getBid(bidId)
    BidStorage-->>Auction: bid
    
    alt Bid not withdrawn
        Auction-->>User: revert BidNotWithdrawn()
    else Before claim block
        Auction-->>User: revert NotClaimable()
    else Valid claim
        Auction->>BidStorage: _updateBid() (set tokensFilled = 0)
        Auction->>Token: transfer(bid.owner, tokensFilled)
        Token-->>Auction: transfer successful
        Auction-->>User: Tokens claimed
    end
```

### Data Structure Relationships

```mermaid
erDiagram
    Demand {
        uint256 currencyDemand
        uint256 tokenDemand
    }
    
    Bid {
        bool exactIn
        uint64 startBlock
        uint64 withdrawnBlock
        uint128 tickId
        address owner
        uint256 amount
        uint256 tokensFilled
    }
    
    Tick {
        uint128 id
        uint128 prev
        uint128 next
        uint256 price
        Demand demand
    }
    
    Checkpoint {
        uint256 clearingPrice
        uint256 blockCleared
        uint256 totalCleared
        uint24 cumulativeMps
        uint256 cumulativeMpsPerPrice
        uint256 resolvedDemandAboveClearingPrice
        uint24 mps
        uint256 prev
    }
    
    Auction {
        Demand sumDemandAboveClearing
    }
    
    Auction ||--o{ Bid : "stores bids"
    Auction ||--o{ Tick : "manages price ticks"
    Auction ||--o{ Checkpoint : "tracks state snapshots"
    Tick ||--|| Demand : "has demand"
    Auction ||--|| Demand : "aggregates demand"
```

### Checkpoint Process

```mermaid
flowchart TD
    A[checkpoint() called] --> B{First bid in block?}
    B -->|No| Z[Return existing checkpoint]
    B -->|Yes| C[Get latestCheckpoint]
    
    C --> D[_advanceToCurrentStep]
    D --> E{block.number >= step.endBlock?}
    E -->|Yes| F[Transform checkpoint with step MPS]
    F --> G[_advanceStep]
    G --> H[Update end block]
    H --> E
    E -->|No| I[Calculate blockTokenSupply]
    
    I --> J[Get sumDemandAboveClearing]
    J --> K[Start with tickUpper]
    K --> L{Demand >= blockTokenSupply?}
    L -->|Yes| M[Subtract tick demand]
    M --> N[Move to next tick]
    N --> O[Update tickUpperId]
    O --> L
    L -->|No| P[_calculateNewClearingPrice]
    
    P --> Q{Demand between ticks?}
    Q -->|Yes| R[Interpolate clearing price:<br/>currencyDemand * tickSpacing /<br/>(blockTokenSupply - tokenDemand)]
    Q -->|No| S[Use tickUpper.price]
    R --> T[Round down to tickSpacing]
    S --> T
    T --> U{Price < floorPrice?}
    U -->|Yes| V[Set to floorPrice]
    U -->|No| W[Keep calculated price]
    V --> X[_updateCheckpoint]
    W --> X
    
    X --> Y[_insertCheckpoint]
    Y --> AA[Emit CheckpointUpdated]
    AA --> Z
```

### Withdraw Bid Decision Flow

```mermaid
flowchart TD
    A[withdrawBid() or<br/>withdrawPartiallyFilledBid()] --> B[Get bid and tick data]
    B --> C{Auction ended?}
    C -->|No| D[revert CannotWithdrawBid]
    C -->|Yes| E{tick.price vs clearingPrice?}
    
    E -->|tick.price > clearingPrice| F[Fully Unfilled Bid]
    E -->|tick.price < clearingPrice| G[Outbid Bid]
    E -->|tick.price == clearingPrice| H[At Clearing Price]
    
    F --> I[Use _getFinalCheckpoint]
    I --> J[_accountFullyFilledCheckpoints<br/>Simple: tokensFilled = 0]
    J --> K[Calculate full refund]
    
    G --> L[Require outbidCheckpointBlock hint]
    L --> M[Validate checkpoint hint]
    M --> N[_accountPartiallyFilledCheckpoints<br/>Complex: iterate checkpoints]
    N --> O[_accountFullyFilledCheckpoints<br/>For remaining period]
    O --> P[Sum tokensFilled and mpsDelta]
    
    H --> Q[Validate checkpoint hints]
    Q --> R[_accountFullyFilledCheckpoints<br/>For fully filled period]
    R --> S[_accountPartiallyFilledCheckpoints<br/>For final partial period]
    S --> T[Sum partial + full fills]
    
    K --> U[_processBidWithdraw]
    P --> U
    T --> U
    U --> V[Update/delete bid storage]
    V --> W[Transfer refund]
    W --> X[Emit BidWithdrawn]
```

### Partial Fill Calculation Detail

```mermaid
flowchart TD
    A[_accountPartiallyFilledCheckpoints] --> B[Get bidDemand and tickDemand<br/>at tick price]
    B --> C[Start with upper checkpoint]
    C --> D{upper.prev != 0?}
    D -->|No| E[Return accumulated values]
    D -->|Yes| F[Get next checkpoint]
    
    F --> G{next.clearingPrice < tick.price?}
    G -->|Yes| H[Found boundary checkpoint]
    G -->|No| I[Calculate partial fill for period]
    
    H --> J[Calculate final period fill:<br/>bidDemand.calculatePartialFill()]
    J --> K[Add to totals and break]
    K --> E
    
    I --> L[Calculate fill for full period:<br/>supply = upper.totalCleared - next.totalCleared<br/>mpsDelta = upper.cumulativeMps - next.cumulativeMps]
    L --> M[bidDemand * supplySoldToTick / tickDemand]
    M --> N[Add to running totals]
    N --> O[Move to next checkpoint]
    O --> C
    
    E --> P[Return: tokensFilled, cumulativeMpsDelta, nextCheckpointBlock]
```

### Clearing Price Calculation Detail

```mermaid
flowchart TD
    A[_calculateNewClearingPrice] --> B[Resolve demand above clearing at tickUpper]
    B --> C[Apply MPS denominator scaling]
    C --> D{resolvedDemand == 0 OR<br/>resolvedDemand == blockTokenSupply?}
    D -->|Yes| E[Perfect match: return tickUpper.price]
    D -->|No| F[Partial match between ticks]
    
    F --> G[Get tickLower demand]
    G --> H[Add tickLower to sumDemand]
    H --> I[Apply MPS scaling to combined demand]
    I --> J[Calculate interpolated price:<br/>currencyDemand * tickSpacing /<br/>(blockTokenSupply - tokenDemand)]
    
    J --> K[Round down to tick boundary:<br/>price - (price % tickSpacing)]
    K --> L{price < floorPrice?}
    L -->|Yes| M[Return floorPrice]
    L -->|No| N[Return calculated price]
    
    E --> O[Final clearing price]
    M --> O
    N --> O
```
