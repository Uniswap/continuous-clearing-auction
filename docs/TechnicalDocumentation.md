# Technical Documentation
CCA documentation is also available on the official [Uniswap docs site](https://docs.uniswap.org/contracts/liquidity-launchpad/CCA).

## Table of Contents
- [Quickstart](#quickstart)
- [Auction Configuration](#auction-configuration)
- [Validation Hooks](#validation-hooks)
- [Internal types](#internal-types)
- [Contract Entrypoints](#auction-entrypoints)
    - [submitBid()](#submitbid)
    - [checkpoint()](#checkpoint)
    - [Exiting a Bid](#exiting-a-bid)
        - [exitBid()](#exitbid)
        - [exitPartiallyFilledBid()](#exitpartiallyfilledbid)
    - [isGraduated()](#isgraduated)
    - [sweepCurrency() and sweepUnsoldTokens()](#sweepcurrency-and-sweepunsoldtokens)
    - [claimTokens()](#claimtokens)
    - [claimTokensBatch()](#claimtokensbatch)
- [Integration guidelines](#integration-guidelines)
    - [Incorrect parameter configurations](#incorrect-parameter-configurations)
    - [Extra funds sent to the auction are not recoverable](#extra-funds-sent-to-the-auction-are-not-recoverable)
    - [Bounds on maximum bid prices](#bounds-on-maximum-bid-prices)
    - [Tick spacing](#tick-spacing)
    - [Auction steps](#auction-steps)
    - [Bidder responsibilities](#bidder-responsibilities)
    - [Limitations with low-decimal tokens or Fee On Transfer tokens](#limitations-with-low-decimal-tokens-or-fee-on-transfer-tokens)

## Quickstart
A comprehensive quickstart guide for deploying and interacting with a local CCA deployment is hosted on the official [Uniswap docs site](https://docs.uniswap.org/contracts/liquidity-launchpad/quickstart/setup).

## Auction Configuration

The auction and its supply curve are configured through the AuctionFactory which deploys individual Auction contracts with configurable parameters.

```solidity
interface IAuctionFactory {
    function initializeDistribution(
        address token,
        uint256 amount,
        bytes calldata configData
    ) external returns (address);
}

/// @notice Parameters for the auction
/// @dev token and totalSupply are passed as constructor arguments
struct AuctionParameters {
    address currency; // token to raise funds in. Use address(0) for ETH
    address tokensRecipient; // address to receive leftover tokens
    address fundsRecipient; // address to receive all raised funds
    uint64 startBlock; // Block which the first step starts
    uint64 endBlock; // When the auction finishes
    uint64 claimBlock; // Block when the auction can claimed
    uint256 tickSpacing; // Fixed granularity for prices
    address validationHook; // Optional hook called before a bid
    uint256 floorPrice; // Starting floor price for the auction
    uint128 requiredCurrencyRaised; // Amount of currency required to be raised for the auction to graduate
    bytes auctionStepsData; // Packed bytes describing token issuance schedule
}

constructor(
    address _token,
    uint128 _totalSupply,
    AuctionParameters memory _parameters
) {}
```

The factory decodes `configData` into `AuctionParameters` and deploys the Auction contract via CREATE2.

## Validation Hooks

Auction creators can set a validation hook to restrict the bids that can be submitted. Hooks MUST revert to signal that the bid is invalid.

A few example hooks are provided in the [periphery](./src/periphery/validationHooks) directory.

### Writing a Validation Hook

Validation hooks must implement the `IValidationHook` interface.

```solidity
interface IValidationHook {
    function validate(uint256 maxPrice, uint128 amount, address owner, address sender, bytes calldata hookData) external;
}
```

Additionally, to increase compatability with other onchain contracts and offchain interfaces, hooks should inherit from `ValidationHookIntrospection`. This provides out of the box support for callers to query support for the `IERC165` and `IValidationHook` interfaces.

To extend this functionality, integrators should override the `supportsInterface` function to signal support for their own custom interface.

```solidity
interface IExampleValidationHook is IValidationHookIntrospection {
    function exampleFunction() external view returns (bool);
}

contract ExampleValidationHook is IExampleValidationHook, ValidationHookIntrospection {
    function validate(uint256 maxPrice, uint128 amount, address owner, address sender, bytes calldata hookData) external {
        // validation logic
    }

    function supportsInterface(bytes4 interfaceId) external view returns (bool) {
        return super.supportsInterface(interfaceId) || interfaceId == type(IExampleValidationHook).interfaceId;
    }
}
```

If a validation hook does not have a custom interface, it MAY return the first four bytes of the hash of its contract name.

## Internal types

### Q96 Fixed-Point Math

The auction uses Q96 fixed-point arithmetic for price and demand representation:

```solidity
library FixedPoint96 {
    uint8 internal constant RESOLUTION = 96;
    uint256 internal constant Q96 = 0x1000000000000000000000000; // 2^96
}
```

- **Price**: Stored as as a Q96 fixed point number to allow for fractional price ratios
- **Demand**: Currency amounts are scaled by Q96 to prevent significant precision loss in calculations

#### MPS terms (Milli-Basis Points)

**MPS = 1e7** (10 million), each representing one thousandth of a basis point:

```solidity
library ConstantsLib {
    uint24 public constant MPS = 1e7; // 10,000,000
}
```

#### ValueX7

A custom uint256 type that represents values which have either been implicitly or explicitly multiplied by 1e7 (ConstantsLib.MPS). These values will be suffixed in the code with `_X7` for clarity.

```solidity
/// @notice A ValueX7 is a uint256 value that has been multiplied by MPS
/// @dev X7 values are used for supply values to avoid intermediate division by MPS
type ValueX7 is uint256;
```

### Auction steps (supply issuance schedule)

The auction steps define the supply issuance schedule. The auction steps are packed into a bytes array and passed to the constructor along with the other parameters. Each step is a packed `uint64` with the first 24 bits being the per-block issuance rate in MPS (milli-bips), and the last 40 bits being the number of blocks to sell over.

```solidity
/// AuctionStepLib.sol

function parse(bytes8 data) internal pure returns (uint24 mps, uint40 blockDelta) {
    mps = uint24(bytes3(data));
    blockDelta = uint40(uint64(data));
}
```

For example, to sell 1 basis point of supply per block for 100 blocks, then 2 basis points for the next 100 blocks, the packed `uint64` would be:

```solidity
uint24 mps = 1000; // 1000 mps = 1 basis point
uint40 blockDelta = 100; // 100 blocks
bytes8 packed1 = uint64(mps) | (uint64(blockDelta) << 24);

mps = 2000; // 2000 mps = 2 basis points
blockDelta = 100; // 100 blocks
bytes8 packed2 = uint64(mps) | (uint64(blockDelta) << 24);

bytes packed = abi.encodePacked(packed1, packed2);
```

The data is deployed to an external SSTORE2 contract for cheaper reads over the lifetime of the auction.

## Contract Entrypoints

### submitBid()

Users can submit bids specifying the currency amount they want to spend. The bid id is returned to the user and can be used to claim tokens or exit the bid. The `prevTickPrice` parameter is used to determine the location of the tick to insert the bid into. The hint must be the price of the tick immediately preceding it in the linked list of prices.

- For convenience, if the `prevTickPrice` is not provided, the contract will iterate through every tick starting from the floor price until it reaches the correct position.
- This will be gas intensive and should not be used unless the caller is sure that `maxPrice` is already initialized, as it will not perform the search.

A bid's `maxPrice` is the maximum price the bidder is willing to pay.
The `amount` is the amount of currency the user is bidding, and `owner` is the address of the user who will receive any purchased tokens or refunded currency.

The Auction enforces the following rules on bid prices:

- Bids must be strictly above the current clearing price
- The maximum bid price must be below the computed MAX_BID_PRICE based on the total supply of the auction.

```solidity
interface IContinuousClearingAuction {
    function submitBid(
        uint256 maxPrice,
        uint128 amount,
        address owner,
        uint256 prevTickPrice,
        bytes calldata hookData
    ) external payable returns (uint256 bidId);

    /// @notice Optional function if the maxPrice is already initialized or if the caller doesn't care about gas efficiency.
    function submitBid(
        uint256 maxPrice,
        uint128 amount,
        address owner,
        bytes calldata hookData
    ) external payable returns (uint256 bidId);
}

event BidSubmitted(uint256 indexed id, address indexed owner, uint256 price, uint256 amount);
event TickInitialized(uint256 price);
```

### checkpoint()

The auction is checkpointed once every block with a new bid. The checkpoint is a snapshot of the auction state up to (NOT including) that block. Checkpoints ultimately determine the token allocations for each bid.

```solidity
interface IContinuousClearingAuction {
    function checkpoint() external returns (Checkpoint memory _checkpoint);
}

event CheckpointUpdated(uint256 indexed blockNumber, uint256 clearingPrice, uint24 cumulativeMps);
```

### Exiting a Bid
Bids can be exited when they are outbid, or when the auction has ended. Exiting a bid will refund any unspent currency to the bid's owner.

#### exitBid()

This function can only be used to exit a bid after the auction has ended, or if the auction does not graduate. Requires that the bid has a maxPrice strictly above the final clearing price of the auction.

```solidity
interface IContinuousClearingAuction {
    /// @notice Exit a bid where max price is above final clearing price
    function exitBid(uint256 bidId) external;
}

event BidExited(uint256 indexed bidId, address indexed owner, uint256 tokensFilled, uint256 currencyRefunded);
```

#### exitPartiallyFilledBid()

Exiting partially filled bids is more complex than above. This function requires the user to provide two checkpoint hints (`lastFullyFilledCheckpointBlock`, `outbidBlock`). These are used to determine the checkpoints immediately before and after the period of time in which the bid was partially filled (auction.clearingPrice == bid.maxPrice).

- `lastFullyFilledCheckpointBlock`: Last checkpoint where clearing price is strictly < bid.maxPrice
- `outbidBlock`: First checkpoint where clearing price is strictly > bid.maxPrice, or 0 if the final clearing price is equal to the bid's max price at the end of the auction, since it was never outbid.

Checkpoints also store a cumulative value (`currencyRaisedAtClearingPriceQ96_X7`) which tracks the amount of currency raised from bids at the clearing price. This is reset every time the clearing price changes, but this is used to determine the user's pro-rata share of the tokens sold at the clearing price.

### isGraduated()

Auctions are graduated if the currency raised meets or exceeds the required threshold set by the auction creator on deployment.

A core invariant of the auction is that no bids can be exited before the auction has graduated.

```solidity
interface IContinuousClearingAuction {
    /// @notice Whether the auction has graduated (currency raised >= required)
    function isGraduated() external view returns (bool);
}
```

### sweepCurrency() and sweepUnsoldTokens()

After an auction ends, raised currency and unsold tokens can be withdrawn to the designated recipients in the auction deployment parameters.

```solidity
interface IContinuousClearingAuction {
    /// @notice Withdraw all raised currency (only for graduated auctions)
    function sweepCurrency() external;

    /// @notice Withdraw any unsold tokens
    function sweepUnsoldTokens() external;
}

event CurrencySwept(address indexed fundsRecipient, uint256 currencyAmount);
event TokensSwept(address indexed tokensRecipient, uint256 tokensAmount);
```

Note:

- `sweepCurrency()` is only callable by anyone after the auction ends, and only for graduated auctions
- `sweepUnsoldTokens()` is callable by anyone after the auction ends and will sweep different amounts depending on graduation.
- For graduated auctions: sweeps all tokens that were not sold per the supply issuance schedule
- For non-graduated auctions: sweeps total supply of tokens

### claimTokens()

Users can claim purchased tokens after the auction's claim block. The bid must be exited before claiming tokens, and the auction must have graduated.

```solidity
interface IContinuousClearingAuction {
    function claimTokens(uint256 bidId) external;
}

event TokensClaimed(uint256 indexed bidId, address indexed owner, uint256 tokensFilled);
```

Anyone can call this function for any valid bid id.

### claimTokensBatch()

Users can claim purchased tokens for multiple bids at once. This is useful to only make one `transfer` call to the owner of the bids. The `owner` parameter must be the same for all bids in the batch.

```solidity
interface IContinuousClearingAuction {
    function claimTokensBatch(address owner, uint256[] calldata bidIds) external;
}

event TokensClaimed(uint256 indexed bidId, address indexed owner, uint256 tokensFilled);
```

Anyone can call this function for any valid bid ids.

## Integration guidelines

### Incorrect parameter configurations

CCA auctions are highly configurable. As such, it is important to ensure that the configurations of each auction instance are not only correct but protect against known risks.

Ensure that the following parameters are correctly set:

- `token` and `currency`
- `totalSupply` is not too large (see [note on total supply and maximum bid price](#note-on-total-supply-and-maximum-bid-price) below)
- `startBlock`, `endBlock`, and `claimBlock`
- `tickSpacing` is not too small (see [note on ticks](#note-on-ticks) below)
- `floorPrice` is correctly set
- `requiredCurrencyRaised` is not set too high where the auction will never graduate
- `auctionStepsData` avoids common pitfalls (see [note on auction steps](#note-on-auction-steps) below)

### Extra funds sent to the auction are not recoverable
Do NOT send more tokens than intended in `totalSupply` to the auction. They will not be recoverable.

Likewise, any `currency` sent directly to the auction and not through `submitBid` will not be lost.

### Bounds on maximum bid prices

The following limitations regarding total supply and maximum bid prices should be considered:

- The maximum total supply that can be sold in the auction is 1e30 wei of `token`. For a token with 18 decimals, this is 1 trillion tokens.
- The auction also ensures that the total currency raised does not exceed the maximum allowable liquidity for a Uniswap v4 liquidity position. The lowest bound for this is 2^107 wei (given the smallest possible tick spacing of 1).

Given a total supply of:

- 1 trillion 18 decimal tokens (1e30), the maximum bid price is 2^110. The max ratio of currency to token is 2^(110-96) = 2^14 = 16384.
- 1 billion 6 decimal tokens (1e15), the maximum bid price is 2^160. The max ratio of currency to token is 2^(160-96) = 2^64 = 18446744073709551616.

We strongly recommend that the `currency` is chosen to be more valuable than `token`, and that the total supply is not excessively large.

### Tick spacing

Ticks in the auction govern where bids can be placed. They have no impact on the potential clearingPrices of the auction and merely serve to prevent users from being outbid by others by infinitesimally small amounts and for gas efficiency in finding new clearing prices.

Generally integrators should choose a tick spacing of AT LEAST 1 basis point of the floor price. 1% or 10% is also reasonable.

Setting too small of a tick spacing will make the auction extremely gas inefficient, and in specific cases, can result in a DoS attack where the auction cannot finish.

### Auction steps

Steps in the auction create the supply issuance schedule. Generally each step should be monotonically increasing in the amount of tokens sold, and the last block of the auction MUST sell a significant amount of tokens.

This is because the final clearing price of the auction is used to initialize a Uniswap v4 liquidity pool, and if only a small number of tokens are sold at the end, the final price will be easy to manipulate.

See the [whitepaper](./assets/whitepaper.pdf) for more details.

### Bidder responsibilities

An Auction can be configured with:

- Excessively high floor prices which would result in a loss of funds for participants.
- Extreme start and end blocks which would prevent bidders from receiving refunds of currency or tokens.
- Honeypot or malicious tokens
- An unrealistic `requiredCurrencyRaised` which would prevent the auction from graduating.
- A `positionRecipient` who will withdraw the liquidity position immediately after the pool is created.

This list is not exhaustive. It is the responsibility of the bidder to validate all parameters before participating in an auction.

### Limitations with low-decimal tokens or Fee On Transfer tokens

Do NOT use the Auction with low-decimal (< 6) tokens. Bidders will lose significant amounts of token due to rounding errors in price and amount calculations.

Fee On Transfer tokens are explicitly not supported as either `token` or `currency`.
