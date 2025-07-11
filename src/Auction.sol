// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

import {FixedPointMathLib} from 'solady/utils/FixedPointMathLib.sol';
import {SafeTransferLib} from 'solady/utils/SafeTransferLib.sol';
import {AuctionStepStorage} from './AuctionStepStorage.sol';
import {AuctionParameters, AuctionStep} from './Base.sol';
import {Tick, TickStorage} from './TickStorage.sol';
import {IAuction} from './interfaces/IAuction.sol';
import {IValidationHook} from './interfaces/IValidationHook.sol';
import {IERC20Minimal} from './interfaces/external/IERC20Minimal.sol';
import {AuctionStepLib} from './libraries/AuctionStepLib.sol';
import {Bid, BidLib} from './libraries/BidLib.sol';
import {Currency, CurrencyLibrary} from './libraries/CurrencyLibrary.sol';

/// @title Auction
contract Auction is IAuction, TickStorage, AuctionStepStorage {
    using FixedPointMathLib for uint128;
    using CurrencyLibrary for Currency;
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

    struct Checkpoint {
        uint256 clearingPrice;
        uint256 totalCleared;
        uint16 cumulativeBps;
    }

    mapping(uint256 blockNumber => Checkpoint) public checkpoints;
    uint256 public lastCheckpointedBlock;

    /// @notice Sum of all demand at or above tickUpper for `currency` (exactIn)
    uint256 public sumCurrencyDemandAtTickUpper;
    /// @notice Sum of all demand at or above tickUpper for `token` (exactOut)
    uint256 public sumTokenDemandAtTickUpper;

    constructor(AuctionParameters memory _parameters) AuctionStepStorage(_parameters.auctionStepsData) {
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

    function clearingPrice() public view returns (uint256) {
        return checkpoints[lastCheckpointedBlock].clearingPrice;
    }

    /// @notice Resolve the token demand at `tickUpper`
    /// @dev This function sums demands from both exactIn and exactOut bids by resolving the exactIn demand at the `tickUpper` price
    ///      and adding all exactOut demand at or above `tickUpper`.
    function _resolvedTokenDemandTickUpper() internal view returns (uint256) {
        return (sumCurrencyDemandAtTickUpper * tickSpacing / ticks[tickUpperId].price) + sumTokenDemandAtTickUpper;
    }

    /// @notice Update the clearing price
    /// @dev This function is called every time a new bid is submitted above the current clearing price
    function _updateClearingPrice() internal {
        if (block.number < startBlock) revert AuctionNotStarted();

        Checkpoint memory _checkpoint = checkpoints[lastCheckpointedBlock];
        // Advance the current step until the current block is within the step
        uint16 sumBps = 0;
        {
            uint256 start = lastCheckpointedBlock;
            uint256 end = step.endBlock;
            while (block.number >= end) {
                // Number of blocks in the old step from the last checkpointed block to the end
                sumBps += uint16(step.bps * (end - start));
                start = end;
                _advanceStep();
                end = step.endBlock;
            }
        }
        // Now current step is the step that contains the current block
        uint256 _totalCleared = _checkpoint.totalCleared;
        uint16 _cumulativeBps = _checkpoint.cumulativeBps;

        uint256 resolvedSupply = step.resolvedSupply(totalSupply, _totalCleared, _cumulativeBps);
        uint256 _aggregateDemand = _resolvedTokenDemandTickUpper();

        Tick memory tickUpper = ticks[tickUpperId];
        while (_aggregateDemand > resolvedSupply && tickUpper.next != 0) {
            // Subtract the demand at the old tickUpper as it has been outbid
            sumCurrencyDemandAtTickUpper -= tickUpper.sumCurrencyDemand;
            sumTokenDemandAtTickUpper -= tickUpper.sumTokenDemand;

            // Advance to the next discovered tick
            tickUpper = ticks[tickUpper.next];
        }

        uint256 _newClearingPrice;
        if (_aggregateDemand < resolvedSupply) {
            // Find the clearing price between the tickLower and tickUpper
            _newClearingPrice =
                (sumCurrencyDemandAtTickUpper / (resolvedSupply - sumTokenDemandAtTickUpper)) * tickSpacing;
            // Round clearingPrice down to the nearest tickSpacing
            _newClearingPrice -= (_newClearingPrice % tickSpacing);
        } else {
            _newClearingPrice = tickUpper.price;
        }

        if (_newClearingPrice < floorPrice) {
            _newClearingPrice = floorPrice;
            _totalCleared += _aggregateDemand;
        } else {
            _totalCleared += resolvedSupply;
        }

        // Add sumBps, the number of bps between the last checkpointed block and the current step's start block
        // Add one because we want to include the current block
        if (step.startBlock > lastCheckpointedBlock) {
            // lastCheckpointedBlock --- | step.startBlock --- | block.number
            //                     ^     ^
            //           cumulativeBps   sumBps
            _cumulativeBps += sumBps + uint16(step.bps * (block.number + 1 - step.startBlock));
        } else {
            // step.startBlock --- | lastCheckpointedBlock --- | block.number
            //                     ^     ^
            //           sumBps (0)   cumulativeBps
            _cumulativeBps += sumBps + uint16(step.bps * (block.number + 1 - lastCheckpointedBlock));
        }

        checkpoints[block.number] =
            Checkpoint({clearingPrice: _newClearingPrice, totalCleared: _totalCleared, cumulativeBps: _cumulativeBps});
        lastCheckpointedBlock = block.number;

        emit CheckpointUpdated(block.number, _newClearingPrice, _totalCleared, _cumulativeBps);
    }

    function _submitBid(uint128 maxPrice, bool exactIn, uint128 amount, address owner, uint128 prevHintId) internal {
        Bid memory bid = Bid({
            maxPrice: maxPrice,
            exactIn: exactIn,
            amount: amount,
            owner: owner,
            startBlock: block.number,
            withdrawnBlock: 0
        });

        bid.validate(floorPrice, tickSpacing);
        
        if (address(validationHook) != address(0)) {
            validationHook.validate(block.number);
        }
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

    /// @inheritdoc IAuction
    function submitBid(uint128 maxPrice, bool exactIn, uint128 amount, address owner, uint128 prevHintId)
        external
        payable
    {
        uint256 resolvedAmount = exactIn ? amount : amount.fullMulDivUp(maxPrice, tickSpacing);
        if (currency.isAddressZero()) {
            if (msg.value != resolvedAmount) revert InvalidAmount();
        } else {
            SafeTransferLib.permit2TransferFrom(Currency.unwrap(currency), owner, address(this), resolvedAmount);
        }
        _submitBid(maxPrice, exactIn, amount, owner, prevHintId);
    }
}
