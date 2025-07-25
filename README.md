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
        PermitSingleForwarder;
    end

    subgraph Libraries
        AuctionStepLib;
        BidLib;
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

    Auction -- inherits from --> PermitSingleForwarder;
    Auction -- inherits from --> TickStorage;
    Auction -- inherits from --> AuctionStepStorage;
    Auction -- implements --> IAuction;

    Auction -- uses --> AuctionStepLib;
    Auction -- uses --> BidLib;
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

    TickStorage -- uses --> BidLib;
    TickStorage -- implements --> ITickStorage;

    PermitSingleForwarder -- implements --> IPermitSingleForwarder;
    PermitSingleForwarder -- interacts with --> IAllowanceTransfer;
```

### Contract Inheritance for Auction.sol

```mermaid
classDiagram
    class PermitSingleForwarder
    class TickStorage
    class AuctionStepStorage
    class IAuction
    Auction --|> PermitSingleForwarder
    Auction --|> TickStorage
    Auction --|> AuctionStepStorage
    Auction --|> IAuction
    class Auction
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
    participant PermitSingleForwarder
    participant IAllowanceTransfer
    participant TickStorage
    participant AuctionStepStorage
    participant IValidationHook

    User->>Auction: submitBid(maxPrice, exactIn, amount, owner, prevHintId)
    alt ERC20 Token
        Auction->>IAllowanceTransfer: permit2TransferFrom(...)
    else ETH
        User-->>Auction: sends ETH with call
    end
    Auction->>PermitSingleForwarder: _submitBid(...)
    PermitSingleForwarder->>IValidationHook: validate(bid)
    PermitSingleForwarder->>AuctionStepStorage: checkpoint()
    AuctionStepStorage->>AuctionStepStorage: _advanceToCurrentStep()
    PermitSingleForwarder->>TickStorage: _initializeTickIfNeeded(...)
    PermitSingleForwarder->>TickStorage: _updateTick(...)
    TickStorage-->>PermitSingleForwarder:
    PermitSingleForwarder-->>Auction:
    Auction-->>User:
```
