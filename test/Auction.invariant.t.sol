// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Auction} from '../src/Auction.sol';
import {AuctionParameters, IAuction} from '../src/interfaces/IAuction.sol';

import {IAuctionStepStorage} from '../src/interfaces/IAuctionStepStorage.sol';
import {IERC20Minimal} from '../src/interfaces/external/IERC20Minimal.sol';
import {Bid, BidLib} from '../src/libraries/BidLib.sol';
import {Currency, CurrencyLibrary} from '../src/libraries/CurrencyLibrary.sol';
import {Test} from 'forge-std/Test.sol';
import {FixedPointMathLib} from 'solady/utils/FixedPointMathLib.sol';

import {Checkpoint} from '../src/libraries/CheckpointLib.sol';
import {Tick} from '../src/libraries/TickLib.sol';
import {AuctionBaseTest} from './utils/AuctionBaseTest.sol';
import {console2} from 'forge-std/console2.sol';
import {ERC20Mock} from 'openzeppelin-contracts/contracts/mocks/token/ERC20Mock.sol';
import {IPermit2} from 'permit2/src/interfaces/IPermit2.sol';

contract AuctionInvariantHandler is Test {
    using CurrencyLibrary for Currency;
    using FixedPointMathLib for uint256;

    Auction public auction;
    IPermit2 public permit2;

    address[] public actors;
    address public currentActor;

    Currency public currency;
    IERC20Minimal public token;

    uint128 public constant BID_MAX_PRICE = type(uint64).max;

    // Ghost variables
    Checkpoint _checkpoint;
    Bid[] _bids;

    constructor(Auction _auction, address[] memory _actors) {
        auction = _auction;
        permit2 = IPermit2(auction.PERMIT2());
        currency = auction.currency();
        token = auction.token();
        actors = _actors;
    }

    modifier useActor(uint256 actorIndexSeed) {
        currentActor = actors[_bound(actorIndexSeed, 0, actors.length - 1)];
        vm.startPrank(currentActor);
        _;
        vm.stopPrank();
    }

    modifier useBid(uint256 bidIndexSeed) {
        Bid memory bid = _bids[_bound(bidIndexSeed, 0, _bids.length - 1)];
        _;
    }

    modifier validateCheckpoint() {
        _;
        Checkpoint memory checkpoint = auction.latestCheckpoint();
        if (checkpoint.clearingPrice != 0) {
            assertGe(checkpoint.clearingPrice, auction.floorPrice());
        }
        // Check that the clearing price is always increasing
        assertGe(checkpoint.clearingPrice, _checkpoint.clearingPrice, 'Checkpoint clearing price is not increasing');
        // Check that the cumulative variables are always increasing
        assertGe(checkpoint.totalCleared, _checkpoint.totalCleared, 'Checkpoint total cleared is not increasing');
        assertGe(checkpoint.cumulativeMps, _checkpoint.cumulativeMps, 'Checkpoint cumulative mps is not increasing');
        assertGe(
            checkpoint.cumulativeMpsPerPrice,
            _checkpoint.cumulativeMpsPerPrice,
            'Checkpoint cumulative mps per price is not increasing'
        );

        _checkpoint = checkpoint;
    }

    /// @notice Generate random values for amount and max price given a desired resolved amount of tokens to purchase
    /// @dev Bounded by purchasing the total supply of tokens and some reasonable max price for bids to prevent overflow
    function useAmountMaxPrice(bool exactIn, uint256 amount, uint256 seed) public view returns (uint256, uint128) {
        uint128 maxPrice = uint128(_bound(seed, auction.floorPrice() + auction.tickSpacing(), BID_MAX_PRICE));
        // Round down to the nearest tick boundary
        maxPrice -= (maxPrice % uint128(auction.tickSpacing()));

        if (exactIn) {
            uint256 inputAmount = amount;
            return (inputAmount, maxPrice);
        } else {
            uint256 inputAmount = amount.fullMulDivUp(maxPrice, auction.tickSpacing());
            return (inputAmount, maxPrice);
        }
    }

    /// @notice Roll the block number
    /// @dev Consider decreasing the probability of this in relation to other functions
    function handleRoll() public {
        vm.roll(block.number + 1);
    }

    /// @notice Handle a bid submission, ensuring that the actor has enough funds and the bid parameters are valid
    function handleSubmitBid(bool exactIn, uint256 actorIndexSeed, uint128 maxPriceSeed)
        public
        payable
        useActor(actorIndexSeed)
        validateCheckpoint
    {
        uint256 amount = maxPriceSeed % auction.totalSupply();
        (uint256 inputAmount, uint128 maxPrice) = useAmountMaxPrice(exactIn, amount, maxPriceSeed);

        if (currency.isAddressZero()) {
            vm.deal(currentActor, inputAmount);
        } else {
            deal(Currency.unwrap(currency), currentActor, inputAmount);
            // Approve the auction to spend the currency
            IERC20Minimal(Currency.unwrap(currency)).approve(address(permit2), type(uint256).max);
            permit2.approve(Currency.unwrap(currency), address(auction), type(uint160).max, type(uint48).max);
        }

        Tick memory lower = auction.getLowerTickForPrice(maxPrice);
        uint128 prevHintId = lower.price == maxPrice ? lower.prev : lower.id;

        try auction.submitBid{value: currency.isAddressZero() ? inputAmount : 0}(
            maxPrice, exactIn, amount, currentActor, prevHintId, bytes('')
        ) {
            _bids.push(
                Bid({
                    exactIn: exactIn,
                    startBlock: uint64(block.number),
                    withdrawnBlock: 0,
                    tickId: auction.getLowerTickForPrice(maxPrice).id,
                    owner: currentActor,
                    amount: amount,
                    tokensFilled: 0
                })
            );
        } catch (bytes memory revertData) {
            if (block.number >= auction.endBlock()) {
                assertEq(revertData, abi.encodeWithSelector(IAuctionStepStorage.AuctionIsOver.selector));
            } else if (inputAmount == 0) {
                assertEq(revertData, abi.encodeWithSelector(IAuction.InvalidAmount.selector));
            } else if (maxPrice <= auction.clearingPrice()) {
                assertEq(revertData, abi.encodeWithSelector(BidLib.InvalidBidPrice.selector));
            }
        }
    }
}

contract AuctionInvariantTest is AuctionBaseTest {
    AuctionInvariantHandler public handler;

    function setUp() public {
        setUpAuction();

        address[] memory actors = new address[](1);
        actors[0] = alice;

        handler = new AuctionInvariantHandler(auction, actors);
        targetContract(address(handler));
    }

    function invariant_canAlwaysCheckpointDuringAuction() public {
        if (block.number > auction.startBlock() && block.number < auction.endBlock()) {
            auction.checkpoint();
        }
    }

    function invariant_allBidsUnderAreWithdrawable() public {
        for (uint256 i = 0; i < handler._bids.length; i++) {
            Bid memory bid = handler._bids[i];
            (,,, uint128 price,) = auction.ticks(bid.tickId);
            if (price < auction.clearingPrice() && bid.withdrawnBlock == 0) {

                auction.withdrawPartiallyFilledBid(bid.id);
            }
        }
    }
}
