// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

import {AuctionStepStorage} from './AuctionStepStorage.sol';
import {AuctionParameters} from './Base.sol';
import {PermitSingleForwarder} from './PermitSingleForwarder.sol';
import {Tick, TickStorage} from './TickStorage.sol';
import {IAuction} from './interfaces/IAuction.sol';

import {IValidationHook} from './interfaces/IValidationHook.sol';
import {IDistributionContract} from './interfaces/external/IDistributionContract.sol';
import {IERC20Minimal} from './interfaces/external/IERC20Minimal.sol';
import {AuctionStep, AuctionStepLib} from './libraries/AuctionStepLib.sol';
import {Bid, BidLib} from './libraries/BidLib.sol';
import {Currency, CurrencyLibrary} from './libraries/CurrencyLibrary.sol';

import {IAllowanceTransfer} from 'permit2/src/interfaces/IAllowanceTransfer.sol';
import {FixedPointMathLib} from 'solady/utils/FixedPointMathLib.sol';
import {SafeTransferLib} from 'solady/utils/SafeTransferLib.sol';

/// @title Auction
contract Auction is PermitSingleForwarder, IAuction, TickStorage, AuctionStepStorage {
    using FixedPointMathLib for uint256;
    using CurrencyLibrary for Currency;
    using BidLib for Bid;
    using AuctionStepLib for *;

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
    /// @notice The block at which purchased tokens can be claimed
    uint64 public immutable claimBlock;
    /// @notice The tick spacing enforced for bid prices
    uint256 public immutable tickSpacing;
    /// @notice An optional hook to be called before a bid is registered
    IValidationHook public immutable validationHook;
    /// @notice The starting price of the auction
    uint256 public immutable floorPrice;

    struct Checkpoint {
        uint256 clearingPrice;
        uint256 blockCleared;
        uint256 totalCleared;
        uint16 cumulativeBps;
    }

    mapping(uint256 blockNumber => Checkpoint) public checkpoints;
    uint256 public lastCheckpointedBlock;

    /// @notice Sum of all demand at or above tickUpper for `currency` (exactIn)
    uint256 public sumCurrencyDemandAtTickUpper;
    /// @notice Sum of all demand at or above tickUpper for `token` (exactOut)
    uint256 public sumTokenDemandAtTickUpper;

    address public constant PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;

    constructor(address _token, uint256 _totalSupply, AuctionParameters memory _parameters)
        AuctionStepStorage(_parameters.auctionStepsData, _parameters.startBlock, _parameters.endBlock)
        PermitSingleForwarder(IAllowanceTransfer(PERMIT2))
    {
        currency = Currency.wrap(_parameters.currency);
        token = IERC20Minimal(_token);
        totalSupply = _totalSupply;
        tokensRecipient = _parameters.tokensRecipient;
        fundsRecipient = _parameters.fundsRecipient;
        claimBlock = _parameters.claimBlock;
        tickSpacing = _parameters.tickSpacing;
        validationHook = IValidationHook(_parameters.validationHook);
        floorPrice = _parameters.floorPrice;

        // Initialize a tick for the floor price
        _initializeTickIfNeeded(0, floorPrice);

        if (totalSupply == 0) revert TotalSupplyIsZero();
        if (floorPrice == 0) revert FloorPriceIsZero();
        if (tickSpacing == 0) revert TickSpacingIsZero();
        if (claimBlock < endBlock) revert ClaimBlockIsBeforeEndBlock();
        if (fundsRecipient == address(0)) revert FundsRecipientIsZero();
    }

    /// @inheritdoc IDistributionContract
    function onTokensReceived(address _token, uint256 _amount) external view {
        if (_token != address(token)) revert IDistributionContract__InvalidToken();
        if (_amount != totalSupply) revert IDistributionContract__InvalidAmount();
        if (token.balanceOf(address(this)) != _amount) revert IDistributionContract__InvalidAmountReceived();
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

    function _advanceToCurrentStep() internal returns (uint256 _totalCleared, uint16 _cumulativeBps) {
        // Advance the current step until the current block is within the step
        Checkpoint memory _checkpoint = checkpoints[lastCheckpointedBlock];
        uint256 start = lastCheckpointedBlock;
        uint256 end = step.endBlock;
        _totalCleared = _checkpoint.totalCleared;
        _cumulativeBps = _checkpoint.cumulativeBps;
        while (block.number >= end) {
            _cumulativeBps += uint16(step.bps * (end - start));
            // Number of tokens cleared in the old step (constant because no change in clearing price)
            _totalCleared += _checkpoint.blockCleared * (end - start);
            start = end;
            _advanceStep();
            end = step.endBlock;
        }
    }

    /// @notice Register a new checkpoint
    /// @dev This function is called every time a new bid is submitted above the current clearing price
    function checkpoint() public {
        if (lastCheckpointedBlock == block.number) return;
        if (block.number < startBlock) revert AuctionNotStarted();

        // Advance to the current step if needed, summing up the results since the last checkpointed block
        (uint256 _totalCleared, uint16 _cumulativeBps) = _advanceToCurrentStep();

        uint256 resolvedSupply = step.resolvedSupply(totalSupply, _totalCleared, _cumulativeBps);
        uint256 aggregateDemand = _resolvedTokenDemandTickUpper().applyBps(step.bps);

        Tick memory tickUpper = ticks[tickUpperId];
        while (aggregateDemand >= resolvedSupply && tickUpper.next != 0) {
            // Subtract the demand at the old tickUpper as it has been outbid
            sumCurrencyDemandAtTickUpper -= tickUpper.sumCurrencyDemand;
            sumTokenDemandAtTickUpper -= tickUpper.sumTokenDemand;

            // Advance to the next discovered tick
            tickUpper = ticks[tickUpper.next];
            aggregateDemand = _resolvedTokenDemandTickUpper().applyBps(step.bps);
        }
        tickUpperId = tickUpper.id;

        uint256 _newClearingPrice;
        // Not enough demand to clear at tickUpper, must be between tickUpper and the tick below it
        if (aggregateDemand < resolvedSupply && aggregateDemand > 0) {
            // Find the clearing price between the tickLower and tickUpper
            _newClearingPrice = (
                (resolvedSupply - sumTokenDemandAtTickUpper.applyBps(step.bps)).fullMulDiv(
                    tickSpacing, sumCurrencyDemandAtTickUpper.applyBps(step.bps)
                )
            );
            // Round clearingPrice down to the nearest tickSpacing
            _newClearingPrice -= (_newClearingPrice % tickSpacing);
        } else {
            _newClearingPrice = tickUpper.price;
        }

        if (_newClearingPrice <= floorPrice) {
            _totalCleared += aggregateDemand;
        } else {
            _totalCleared += resolvedSupply;
        }

        // We already accounted for the bps between the last checkpointed block and the current step's start block
        // Add one because we want to include the current block in the sum
        if (step.startBlock > lastCheckpointedBlock) {
            // lastCheckpointedBlock --- | step.startBlock --- | block.number
            //                     ^     ^
            //           cumulativeBps   sumBps
            _cumulativeBps += uint16(step.bps * (block.number - step.startBlock));
        } else {
            // step.startBlock --------- | lastCheckpointedBlock --- | block.number
            //                ^          ^
            //           sumBps (0)   cumulativeBps
            _cumulativeBps += uint16(step.bps * (block.number - lastCheckpointedBlock));
        }

        checkpoints[block.number] = Checkpoint({
            clearingPrice: _newClearingPrice,
            blockCleared: _newClearingPrice < floorPrice ? aggregateDemand : resolvedSupply,
            totalCleared: _totalCleared,
            cumulativeBps: _cumulativeBps
        });
        lastCheckpointedBlock = block.number;

        emit CheckpointUpdated(block.number, _newClearingPrice, _totalCleared, _cumulativeBps);
    }

    function _submitBid(uint128 maxPrice, bool exactIn, uint256 amount, address owner, uint128 prevHintId) internal {
        Bid memory bid =
            Bid({exactIn: exactIn, amount: amount, owner: owner, startBlock: uint64(block.number), withdrawnBlock: 0});

        BidLib.validate(maxPrice, floorPrice, tickSpacing);

        if (address(validationHook) != address(0)) {
            validationHook.validate(bid);
        }

        // First bid in a block updates the clearing price
        checkpoint();

        uint128 tickId = _initializeTickIfNeeded(prevHintId, maxPrice);
        _updateTick(tickId, bid);

        // Only bids higher than the clearing price can change the clearing price
        if (maxPrice >= ticks[tickUpperId].price) {
            if (bid.exactIn) {
                sumCurrencyDemandAtTickUpper += bid.amount;
            } else {
                sumTokenDemandAtTickUpper += bid.amount;
            }
        }

        emit BidSubmitted(tickId, maxPrice, bid.exactIn, bid.amount);
    }

    /// @inheritdoc IAuction
    function submitBid(uint128 maxPrice, bool exactIn, uint256 amount, address owner, uint128 prevHintId)
        external
        payable
    {
        uint256 resolvedAmount = exactIn ? amount : amount.fullMulDivUp(maxPrice, tickSpacing);
        if (currency.isAddressZero()) {
            if (msg.value != resolvedAmount) revert InvalidAmount();
        } else {
            SafeTransferLib.permit2TransferFrom(Currency.unwrap(currency), msg.sender, address(this), resolvedAmount);
        }
        _submitBid(maxPrice, exactIn, amount, owner, prevHintId);
    }
}
