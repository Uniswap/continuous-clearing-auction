// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

import {AuctionStepStorage} from './AuctionStepStorage.sol';
import {AuctionParameters} from './Base.sol';

import {BidStorage} from './BidStorage.sol';
import {Checkpoint, CheckpointStorage} from './CheckpointStorage.sol';
import {PermitSingleForwarder} from './PermitSingleForwarder.sol';
import {Tick, TickStorage} from './TickStorage.sol';
import {IAuction} from './interfaces/IAuction.sol';

import {IValidationHook} from './interfaces/IValidationHook.sol';
import {IDistributionContract} from './interfaces/external/IDistributionContract.sol';
import {IERC20Minimal} from './interfaces/external/IERC20Minimal.sol';
import {AuctionStepLib} from './libraries/AuctionStepLib.sol';
import {Bid, BidLib} from './libraries/BidLib.sol';
import {Currency, CurrencyLibrary} from './libraries/CurrencyLibrary.sol';

import {IAllowanceTransfer} from 'permit2/src/interfaces/IAllowanceTransfer.sol';
import {FixedPointMathLib} from 'solady/utils/FixedPointMathLib.sol';
import {SafeTransferLib} from 'solady/utils/SafeTransferLib.sol';

/// @title Auction
contract Auction is PermitSingleForwarder, IAuction, TickStorage, AuctionStepStorage, BidStorage, CheckpointStorage {
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
        return latestCheckpoint().clearingPrice;
    }

    /// @notice Resolve the token demand at `tickUpper`
    /// @dev This function sums demands from both exactIn and exactOut bids by resolving the exactIn demand at the `tickUpper` price
    ///      and adding all exactOut demand at or above `tickUpper`.
    function _resolvedTokenDemandTickUpper() internal view returns (uint256) {
        return (sumCurrencyDemandAtTickUpper * tickSpacing / ticks[tickUpperId].price) + sumTokenDemandAtTickUpper;
    }

    function _advanceToCurrentStep()
        internal
        returns (uint256 _totalCleared, uint24 _cumulativeMps, uint256 _cumulativeMpsPerPrice)
    {
        // Advance the current step until the current block is within the step
        Checkpoint memory _checkpoint = latestCheckpoint();
        uint256 start = lastCheckpointedBlock;
        uint256 end = step.endBlock;
        _totalCleared = _checkpoint.totalCleared;
        _cumulativeMps = _checkpoint.cumulativeMps;
        _cumulativeMpsPerPrice = _checkpoint.cumulativeMpsPerPrice;

        while (block.number >= end) {
            uint256 delta = end - start;
            // All are constant since no change in clearing price
            // If no tokens have been cleared yet, we don't need to update the cumulative values
            if (_checkpoint.clearingPrice > 0) {
                uint24 deltaMps = uint24(step.mps * delta);
                _cumulativeMps += deltaMps;
                _totalCleared += _checkpoint.blockCleared * delta;
                _cumulativeMpsPerPrice += uint256(deltaMps).fullMulDiv(BidLib.PRECISION, _checkpoint.clearingPrice);
            }
            start = end;
            _advanceStep();
            end = step.endBlock;
        }
    }

    /// @notice Register a new checkpoint
    /// @dev This function is called every time a new bid is submitted above the current clearing price
    function checkpoint() public {
        uint256 _lastCheckpointedBlock = lastCheckpointedBlock;
        if (_lastCheckpointedBlock == block.number) return;
        if (block.number < startBlock) revert AuctionNotStarted();

        // Advance to the current step if needed, summing up the results since the last checkpointed block
        (uint256 _totalCleared, uint24 _cumulativeMps, uint256 _cumulativeMpsPerPrice) = _advanceToCurrentStep();

        uint256 resolvedSupply = step.resolvedSupply(totalSupply, _totalCleared, _cumulativeMps);
        uint256 aggregateDemand = _resolvedTokenDemandTickUpper().applyMps(step.mps);

        Tick memory tickUpper = ticks[tickUpperId];
        while (aggregateDemand >= resolvedSupply && tickUpper.next != 0) {
            // Subtract the demand at the old tickUpper as it has been outbid
            sumCurrencyDemandAtTickUpper -= tickUpper.sumCurrencyDemand;
            sumTokenDemandAtTickUpper -= tickUpper.sumTokenDemand;

            // Advance to the next discovered tick
            tickUpper = ticks[tickUpper.next];
            aggregateDemand = _resolvedTokenDemandTickUpper().applyMps(step.mps);
        }
        tickUpperId = tickUpper.id;

        uint256 _newClearingPrice;
        // Not enough demand to clear at tickUpper, must be between tickUpper and the tick below it
        if (aggregateDemand < resolvedSupply && aggregateDemand > 0) {
            // Find the clearing price between the tickLower and tickUpper
            _newClearingPrice = (
                (resolvedSupply - sumTokenDemandAtTickUpper.applyMps(step.mps)).fullMulDiv(
                    tickSpacing, sumCurrencyDemandAtTickUpper.applyMps(step.mps)
                )
            );
            // Round clearingPrice down to the nearest tickSpacing
            _newClearingPrice -= (_newClearingPrice % tickSpacing);
        } else {
            _newClearingPrice = tickUpper.price;
        }

        // If the clearing price is below the floorPrice, set it to the floorPrice
        if (_newClearingPrice <= floorPrice) {
            _newClearingPrice = floorPrice;
            // We can only clear the current demand at the floor price
            _totalCleared += aggregateDemand;
        } else {
            // Otherwise, we can clear the entire supply being sold in the block
            _totalCleared += resolvedSupply;
        }

        uint24 mpsSinceLastCheckpoint;
        if (step.startBlock > _lastCheckpointedBlock) {
            // lastCheckpointedBlock --- | step.startBlock --- | block.number
            //                     ^     ^
            //           cumulativeMps   sumMps
            mpsSinceLastCheckpoint = uint24(step.mps * (block.number - step.startBlock));
        } else {
            // step.startBlock --------- | lastCheckpointedBlock --- | block.number
            //                ^          ^
            //           sumMps (0)   cumulativeMps
            mpsSinceLastCheckpoint = uint24(step.mps * (block.number - _lastCheckpointedBlock));
        }
        _cumulativeMps += mpsSinceLastCheckpoint;

        uint256 newCumulativeMpsPerPrice =
            _cumulativeMpsPerPrice + (uint256(mpsSinceLastCheckpoint).fullMulDiv(BidLib.PRECISION, _newClearingPrice));

        _insertCheckpoint(
            Checkpoint({
                clearingPrice: _newClearingPrice,
                blockCleared: _newClearingPrice < floorPrice ? aggregateDemand : resolvedSupply,
                totalCleared: _totalCleared,
                cumulativeMps: _cumulativeMps,
                cumulativeMpsPerPrice: newCumulativeMpsPerPrice,
                prev: _lastCheckpointedBlock
            })
        );

        emit CheckpointUpdated(block.number, _newClearingPrice, _totalCleared, _cumulativeMps);
    }

    function _submitBid(
        uint128 maxPrice,
        bool exactIn,
        uint256 amount,
        address owner,
        uint128 prevHintId,
        bytes calldata hookData
    ) internal returns (uint256 bidId) {
        // First bid in a block updates the clearing price
        checkpoint();

        uint128 tickId = _initializeTickIfNeeded(prevHintId, maxPrice);

        Bid memory bid = Bid({
            exactIn: exactIn,
            startBlock: uint64(block.number),
            withdrawnBlock: 0,
            tickId: tickId,
            amount: amount,
            owner: owner,
            tokensFilled: 0
        });

        if (address(validationHook) != address(0)) {
            validationHook.validate(bid, hookData);
        }

        BidLib.validate(maxPrice, floorPrice, tickSpacing);
        _updateTick(tickId, bid);
        bidId = _createBid(bid);

        // Only bids higher than the clearing price can change the clearing price
        if (maxPrice >= ticks[tickUpperId].price) {
            if (bid.exactIn) {
                sumCurrencyDemandAtTickUpper += bid.amount;
            } else {
                sumTokenDemandAtTickUpper += bid.amount;
            }
        }

        emit BidSubmitted(bidId, owner, maxPrice, bid.exactIn, bid.amount);
    }

    /// @inheritdoc IAuction
    function submitBid(
        uint128 maxPrice,
        bool exactIn,
        uint256 amount,
        address owner,
        uint128 prevHintId,
        bytes calldata hookData
    ) external payable returns (uint256) {
        uint256 resolvedAmount = exactIn ? amount : amount.fullMulDivUp(maxPrice, tickSpacing);
        if (currency.isAddressZero()) {
            if (msg.value != resolvedAmount) revert InvalidAmount();
        } else {
            SafeTransferLib.permit2TransferFrom(Currency.unwrap(currency), msg.sender, address(this), resolvedAmount);
        }
        return _submitBid(maxPrice, exactIn, amount, owner, prevHintId, hookData);
    }

    /// @inheritdoc IAuction
    function withdrawBid(uint256 bidId, uint256 upperCheckpointBlock) external {
        Bid memory bid = _getBid(bidId);
        uint256 maxPrice = ticks[bid.tickId].price;
        if (bid.owner != msg.sender) revert NotBidOwner();
        if (bid.withdrawnBlock != 0) revert BidAlreadyWithdrawn();

        // Can only withdraw if the bid is below the clearing price
        if (maxPrice >= clearingPrice()) revert CannotWithdrawBid();

        // Require that the upperCheckpoint is the checkpoint immediately after the last active checkpoint for the bid
        Checkpoint memory upperCheckpoint = _getCheckpoint(upperCheckpointBlock);
        Checkpoint memory lastValidCheckpoint = _getCheckpoint(upperCheckpoint.prev);

        if (upperCheckpoint.clearingPrice < maxPrice || lastValidCheckpoint.clearingPrice >= maxPrice) {
            revert InvalidCheckpointHint();
        }

        // Starting checkpoint must exist because we checkpoint on bid submission
        Checkpoint memory startCheckpoint = _getCheckpoint(bid.startBlock);

        (uint256 tokensFilled, uint256 refund) = bid.resolve(
            maxPrice,
            lastValidCheckpoint.cumulativeMpsPerPrice - startCheckpoint.cumulativeMpsPerPrice,
            lastValidCheckpoint.cumulativeMps - startCheckpoint.cumulativeMps
        );

        currency.transfer(bid.owner, refund);

        bid.tokensFilled = tokensFilled;
        bid.withdrawnBlock = uint64(block.number);

        _updateBid(bidId, bid);

        emit BidWithdrawn(bidId, msg.sender);
    }

    /// @inheritdoc IAuction
    function claimTokens(uint256 bidId) external {
        Bid memory bid = _getBid(bidId);
        if (bid.withdrawnBlock == 0) revert BidNotWithdrawn();
        if (block.number < claimBlock) revert NotClaimable();

        uint256 tokensFilled = bid.tokensFilled;
        bid.tokensFilled = 0;
        _updateBid(bidId, bid);

        token.transfer(bid.owner, tokensFilled);

        emit TokensClaimed(bid.owner, tokensFilled);
    }

    receive() external payable {}
}
