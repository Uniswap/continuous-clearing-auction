// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

import {AuctionParameters, AuctionStep} from './Base.sol';
import {Tick, TickStorage} from './TickStorage.sol';
import {IAuction} from './interfaces/IAuction.sol';
import {IValidationHook} from './interfaces/IValidationHook.sol';
import {IERC20Minimal} from './interfaces/external/IERC20Minimal.sol';

import {AuctionStepLib} from './libraries/AuctionStepLib.sol';
import {Bid, BidLib} from './libraries/BidLib.sol';
import {Currency} from './libraries/CurrencyLibrary.sol';

/// @title Auction
contract Auction is IAuction, TickStorage {
    using BidLib for Bid;
    using AuctionStepLib for bytes;
    using AuctionStepLib for AuctionStep;

    /// @notice The currency of the auction
    Currency public immutable currency;
    /// @notice The token of the auction
    IERC20Minimal public immutable token;
    /// @notice The total supply of token to sell
    uint256 public immutable totalSupply;
    /// @notice The recipient of any unsold tokens
    address public immutable tokensRecipient;
    /// @notice The recipient of the funds from the auction
    address public immutable fundsRecipient;
    /// @notice The block at which the auction starts
    uint256 public immutable startBlock;
    /// @notice The block at which the auction ends
    uint256 public immutable endBlock;
    /// @notice The block at which purchased tokens can be claimed
    uint256 public immutable claimBlock;
    /// @notice The tick spacing enforced for bid prices
    uint256 public immutable tickSpacing;
    /// @notice An optional hook to be called before a bid is registered
    IValidationHook public immutable validationHook;
    /// @notice The starting price of the auction
    uint256 public immutable floorPrice;

    /// @notice The auction steps data from contructor parameters
    bytes public auctionStepsData;
    /// @notice The current step data
    AuctionStep public step;
    /// @notice Singly linked list of auction steps
    mapping(uint256 id => AuctionStep) public steps;
    /// @notice The id of the first step
    uint256 public headId;
    /// @notice The word offset of the last read step in `auctionStepsData` bytes
    uint256 public offset;

    /// @notice The cumulative amount of tokens cleared
    uint256 public totalCleared;
    /// @notice The cumulative basis points of past auction steps
    uint256 public sumBps;

    /// @notice The current clearing price
    uint256 public clearingPrice;
    /// @notice Sum of all demand at or above tickUpper for `currency` (exactIn)
    uint256 public sumCurrencyDemandAtTickUpper;
    /// @notice Sum of all demand at or above tickUpper for `token` (exactOut)
    uint256 public sumTokenDemandAtTickUpper;

    constructor(AuctionParameters memory _parameters) {
        currency = Currency.wrap(_parameters.currency);
        token = IERC20Minimal(_parameters.token);
        totalSupply = _parameters.totalSupply;
        tokensRecipient = _parameters.tokensRecipient;
        fundsRecipient = _parameters.fundsRecipient;
        startBlock = _parameters.startBlock;
        endBlock = _parameters.endBlock;
        claimBlock = _parameters.claimBlock;
        tickSpacing = _parameters.tickSpacing;
        validationHook = IValidationHook(_parameters.validationHook);
        floorPrice = _parameters.floorPrice;
        auctionStepsData = _parameters.auctionStepsData;

        // Initialize a tick for the floor price
        _initializeTickIfNeeded(0, floorPrice);

        if (totalSupply == 0) revert TotalSupplyIsZero();
        if (floorPrice == 0) revert FloorPriceIsZero();
        if (tickSpacing == 0) revert TickSpacingIsZero();
        if (endBlock <= startBlock) revert EndBlockIsBeforeStartBlock();
        if (endBlock > type(uint256).max) revert EndBlockIsTooLarge();
        if (claimBlock < endBlock) revert ClaimBlockIsBeforeEndBlock();
        if (tokensRecipient == address(0)) revert TokenRecipientIsZero();
        if (fundsRecipient == address(0)) revert FundsRecipientIsZero();
    }

    /// @notice Resolve the token demand at `tickUpper`
    /// @dev This function sums demands from both exactIn and exactOut bids by resolving the exactIn demand at the `tickUpper` price
    ///      and adding all exactOut demand at or above `tickUpper`.
    function _resolvedTokenDemandTickUpper() internal view returns (uint256) {
        return (sumCurrencyDemandAtTickUpper * tickSpacing / ticks[tickUpperId].price) + sumTokenDemandAtTickUpper;
    }

    /// @notice Record the current step in the auction and advance to the next one
    /// @dev This function is called on every new bid if the current step is complete
    function _recordStep() internal {
        if (block.number < startBlock) revert AuctionNotStarted();
        if (block.number < step.endBlock) revert AuctionStepNotOver();

        AuctionStep memory currentStep = step;

        // Write current data to step
        currentStep.clearingPrice = clearingPrice;
        if (currentStep.bps > 0) {
            if (clearingPrice > floorPrice) {
                currentStep.amountCleared = currentStep.resolvedSupply(totalSupply, totalCleared, sumBps);
            } else {
                // not fully cleared
                currentStep.amountCleared = _resolvedTokenDemandTickUpper();
            }
            // Update global state
            totalCleared += currentStep.amountCleared;
            sumBps += currentStep.bps;
        }

        uint256 _id = currentStep.id;
        offset = _id * 8; // offset is the pointer to the next step in the auctionStepsData. Each step is a uint64 (8 bytes)
        uint256 _offset = offset;

        bytes memory _auctionStepsData = auctionStepsData;
        if (_offset >= _auctionStepsData.length) revert AuctionIsOver();
        (uint16 bps, uint48 blockDelta) = _auctionStepsData.get(_offset);

        _id++;
        uint256 _startBlock = block.number;
        uint256 _endBlock = _startBlock + blockDelta;

        currentStep.id = _id;
        currentStep.bps = bps;
        currentStep.startBlock = _startBlock;
        currentStep.endBlock = _endBlock;
        currentStep.next = steps[headId].next;
        steps[headId].next = _id;
        headId = _id;

        step = currentStep;

        emit AuctionStepRecorded(_id, _startBlock, _endBlock);
    }

    /// @notice Update the clearing price
    /// @dev This function is called every time a new bid is submitted above the current clearing price
    function _updateClearingPrice() internal {
        uint256 resolvedSupply = step.resolvedSupply(totalSupply, totalCleared, sumBps);
        uint256 _aggregateDemand = _resolvedTokenDemandTickUpper();

        Tick memory tickUpper = ticks[tickUpperId];
        while (_aggregateDemand >= resolvedSupply && tickUpper.next != 0) {
            // Subtract the demand at the old tickUpper as it has been outbid
            sumCurrencyDemandAtTickUpper -= tickUpper.sumCurrencyDemand;
            sumTokenDemandAtTickUpper -= tickUpper.sumTokenDemand;

            // Advance to the next discovered tick
            tickUpper = ticks[tickUpper.next];
        }

        uint256 _clearingPrice;
        if (_aggregateDemand < resolvedSupply) {
            // Find the clearing price between the tickLower and tickUpper
            _clearingPrice = (sumCurrencyDemandAtTickUpper / (resolvedSupply - sumTokenDemandAtTickUpper)) * tickSpacing;
            // Round clearingPrice down to the nearest tickSpacing
            _clearingPrice -= (_clearingPrice % tickSpacing);
        } else {
            _clearingPrice = tickUpper.price;
        }

        if (_clearingPrice < floorPrice) _clearingPrice = floorPrice;
        uint256 _oldClearingPrice = clearingPrice;
        if (_clearingPrice > _oldClearingPrice) {
            emit ClearingPriceUpdated(_oldClearingPrice, _clearingPrice);
            clearingPrice = _clearingPrice;
        }
    }

    /// @inheritdoc IAuction
    function submitBid(uint128 maxPrice, bool exactIn, uint128 amount, address owner, uint128 prevHintId) external {
        Bid memory bid = Bid({
            maxPrice: maxPrice,
            exactIn: exactIn,
            amount: amount,
            owner: owner,
            startStepId: step.id,
            withdrawnStepId: 0
        });
        bid.validate(floorPrice, tickSpacing);

        if (address(validationHook) != address(0)) {
            validationHook.validate(block.number);
        }

        if (block.number >= step.endBlock) _recordStep();

        uint128 id = _initializeTickIfNeeded(prevHintId, bid.maxPrice);
        _updateTick(id, bid);

        // Only bids higher than the clearing price can change the clearing price
        if (bid.maxPrice >= ticks[tickUpperId].price) {
            if (bid.exactIn) {
                sumCurrencyDemandAtTickUpper += bid.amount;
            } else {
                sumTokenDemandAtTickUpper += bid.amount;
            }
            _updateClearingPrice();
        }

        emit BidSubmitted(id, bid.maxPrice, bid.exactIn, bid.amount);
    }
}
