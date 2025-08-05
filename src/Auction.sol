// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

import {console2} from 'forge-std/console2.sol';
import {AuctionStepStorage} from './AuctionStepStorage.sol';
import {BidStorage} from './BidStorage.sol';
import {Checkpoint, CheckpointStorage} from './CheckpointStorage.sol';
import {PermitSingleForwarder} from './PermitSingleForwarder.sol';
import {TickStorage} from './TickStorage.sol';

import {AuctionParameters, IAuction} from './interfaces/IAuction.sol';
import {Tick, TickLib} from './libraries/TickLib.sol';

import {IValidationHook} from './interfaces/IValidationHook.sol';
import {IDistributionContract} from './interfaces/external/IDistributionContract.sol';
import {IERC20Minimal} from './interfaces/external/IERC20Minimal.sol';
import {AuctionStepLib} from './libraries/AuctionStepLib.sol';
import {Bid, BidLib} from './libraries/BidLib.sol';

import {CheckpointLib} from './libraries/CheckpointLib.sol';
import {Currency, CurrencyLibrary} from './libraries/CurrencyLibrary.sol';
import {Demand, DemandLib} from './libraries/DemandLib.sol';

import {IAllowanceTransfer} from 'permit2/src/interfaces/IAllowanceTransfer.sol';
import {FixedPointMathLib} from 'solady/utils/FixedPointMathLib.sol';
import {SafeTransferLib} from 'solady/utils/SafeTransferLib.sol';

/// @title Auction
contract Auction is PermitSingleForwarder, IAuction, TickStorage, AuctionStepStorage, BidStorage, CheckpointStorage {
    using FixedPointMathLib for uint256;
    using CurrencyLibrary for Currency;
    using TickLib for Tick;
    using BidLib for Bid;
    using AuctionStepLib for *;
    using CheckpointLib for Checkpoint;
    using DemandLib for Demand;

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

    Demand public sumDemandTickUpper;

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

    /// @notice Advance the current step until the current block is within the step
    function _advanceToCurrentStep() internal returns (Checkpoint memory _checkpoint) {
        // Advance the current step until the current block is within the step
        _checkpoint = latestCheckpoint();
        uint256 start = lastCheckpointedBlock;
        uint256 end = step.endBlock;

        while (block.number >= end) {
            if (_checkpoint.clearingPrice > 0) {
                _checkpoint = _checkpoint.transform(end - start, step.mps);
            }
            start = end;
            _advanceStep();
            end = step.endBlock;
        }
    }

    /// @notice Register a new checkpoint
    /// @dev This function is called every time a new bid is submitted above the current clearing price
    function checkpoint() public returns (Checkpoint memory _checkpoint) {
        uint256 _lastCheckpointedBlock = lastCheckpointedBlock;
        if (_lastCheckpointedBlock == block.number) return latestCheckpoint();
        if (block.number < startBlock) revert AuctionNotStarted();

        // Advance to the current step if needed, summing up the results since the last checkpointed block
        _checkpoint = _advanceToCurrentStep();

        Demand memory _sumDemandTickUpper = sumDemandTickUpper;
        Tick memory _tickUpper = ticks[tickUpperId];

        uint256 blockTokenSupply = step.resolvedSupply(totalSupply, _checkpoint.totalCleared, _checkpoint.cumulativeMps);
        uint256 blockAggregateDemand = _sumDemandTickUpper.resolve(_tickUpper.price, tickSpacing).applyMps(step.mps);

        while (blockAggregateDemand >= blockTokenSupply && _tickUpper.next != 0) {
            // Subtract the demand at the old tickUpper as it has been outbid
            _sumDemandTickUpper = _sumDemandTickUpper.sub(_tickUpper.demand);

            // Advance to the next discovered tick
            _tickUpper = ticks[_tickUpper.next];
            blockAggregateDemand = _sumDemandTickUpper.resolve(_tickUpper.price, tickSpacing).applyMps(step.mps);
        }
        tickUpperId = _tickUpper.id;

        uint256 _newClearingPrice;
        // Not enough demand to clear at tickUpper, must be between tickUpper and the tick below it
        // > 0 check to prevent div by 0 error
        if (blockAggregateDemand < blockTokenSupply && blockAggregateDemand > 0) {
            // Find the clearing price between the tickLower and tickUpper
            _newClearingPrice = (
                (blockTokenSupply - _sumDemandTickUpper.tokenDemand.applyMps(step.mps)).fullMulDiv(
                    tickSpacing, _sumDemandTickUpper.currencyDemand.applyMps(step.mps)
                )
            );
            // Round clearingPrice down to the nearest tickSpacing
            _newClearingPrice -= (_newClearingPrice % tickSpacing);
        } else if (blockAggregateDemand == blockTokenSupply) {
            _newClearingPrice = _tickUpper.price;
        }

        console2.log('blockAggregateDemand', blockAggregateDemand);
        console2.log('blockTokenSupply', blockTokenSupply);
        console2.log('newClearingPrice', _newClearingPrice);

        // If the clearing price is below the floorPrice, set it to the floorPrice
        if (_newClearingPrice < floorPrice) {
            _checkpoint.clearingPrice = floorPrice;
            // We can only clear the current demand at the floor price
            _checkpoint.totalCleared += blockAggregateDemand;
        }
        // Otherwise, we can clear the entire supply being sold in the block
        else if (_newClearingPrice >= _checkpoint.clearingPrice) {
            _checkpoint.clearingPrice = _newClearingPrice;
            _checkpoint.totalCleared += blockTokenSupply;
        }

        console2.log('clearingPrice', _checkpoint.clearingPrice);
        console2.log('totalCleared', _checkpoint.totalCleared);

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

        _checkpoint.cumulativeMps += mpsSinceLastCheckpoint;
        _checkpoint.cumulativeMpsPerPrice +=
            uint256(mpsSinceLastCheckpoint).fullMulDiv(BidLib.PRECISION, _checkpoint.clearingPrice);
        _checkpoint.aggregateActiveDemand = _sumDemandTickUpper.resolve(_tickUpper.price, tickSpacing)
            + _sumDemandTickUpper.resolve(ticks[_tickUpper.prev].price, tickSpacing);

        _insertCheckpoint(_checkpoint);

        sumDemandTickUpper = _sumDemandTickUpper;

        emit CheckpointUpdated(
            block.number, _checkpoint.clearingPrice, _checkpoint.totalCleared, _checkpoint.cumulativeMps
        );
    }

    function _submitBid(
        uint128 maxPrice,
        bool exactIn,
        uint256 amount,
        address owner,
        uint128 prevHintId,
        bytes calldata hookData
    ) internal {
        // First bid in a block updates the clearing price
        checkpoint();

        uint128 tickId = _initializeTickIfNeeded(prevHintId, maxPrice);

        if (address(validationHook) != address(0)) {
            validationHook.validate(maxPrice, exactIn, amount, owner, msg.sender, hookData);
        }

        BidLib.validate(maxPrice, floorPrice, tickSpacing);

        _updateTick(tickId, exactIn, amount);

        uint256 bidId = _createBid(exactIn, amount, owner, tickId);

        // Only bids higher than the clearing price can change the clearing price
        if (maxPrice >= ticks[tickUpperId].price) {
            if (exactIn) {
                sumDemandTickUpper = sumDemandTickUpper.addCurrencyAmount(amount);
            } else {
                sumDemandTickUpper = sumDemandTickUpper.addTokenAmount(amount);
            }
        }

        emit BidSubmitted(bidId, owner, maxPrice, exactIn, amount);
    }

    /// @inheritdoc IAuction
    function submitBid(
        uint128 maxPrice,
        bool exactIn,
        uint256 amount,
        address owner,
        uint128 prevHintId,
        bytes calldata hookData
    ) external payable {
        uint256 resolvedAmount = exactIn ? amount : amount.fullMulDivUp(maxPrice, tickSpacing);
        if (currency.isAddressZero()) {
            if (msg.value != resolvedAmount) revert InvalidAmount();
        } else {
            SafeTransferLib.permit2TransferFrom(Currency.unwrap(currency), msg.sender, address(this), resolvedAmount);
        }
        _submitBid(maxPrice, exactIn, amount, owner, prevHintId, hookData);
    }

    /// @inheritdoc IAuction
    function withdrawBid(uint256 bidId, uint256 upperCheckpointBlock) external {
        Bid memory bid = _getBid(bidId);
        if (bid.withdrawnBlock != 0) revert BidAlreadyWithdrawn();

        Tick memory tick = ticks[bid.tickId];

        // Starting checkpoint must exist because we checkpoint on bid submission
        Checkpoint memory startCheckpoint = _getCheckpoint(bid.startBlock);
        Checkpoint memory upperCheckpoint = _getCheckpoint(upperCheckpointBlock);
        Checkpoint memory lastValidCheckpoint = _getCheckpoint(upperCheckpoint.prev);
        if (upperCheckpoint.clearingPrice < tick.price || lastValidCheckpoint.clearingPrice >= tick.price) {
            revert InvalidCheckpointHint();
        }

        uint256 tokensFilled;
        uint256 refund;
        uint256 _clearingPrice = clearingPrice();
        /// @dev Bid was fully filled the checkpoint under UpperCheckpoint
        if (tick.price < _clearingPrice) {
            (tokensFilled, refund) = bid.resolve(
                tick.price,
                lastValidCheckpoint.cumulativeMpsPerPrice - startCheckpoint.cumulativeMpsPerPrice,
                lastValidCheckpoint.cumulativeMps - startCheckpoint.cumulativeMps
            );
        }
        /// @dev Bid was fully filled and the auction is now over
        else if (tick.price > _clearingPrice && block.number > endBlock) {
            Checkpoint memory finalCheckpoint = latestCheckpoint().transform(endBlock - lastCheckpointedBlock, step.mps);
            (tokensFilled, refund) = bid.resolve(
                tick.price,
                finalCheckpoint.cumulativeMpsPerPrice - startCheckpoint.cumulativeMpsPerPrice,
                finalCheckpoint.cumulativeMps - startCheckpoint.cumulativeMps
            );
        } else if (tick.price == _clearingPrice && block.number > endBlock) {
            // lastValidCheckpoint --- ... | upperCheckpoint --- ... | latestCheckpoint ... | endBlock
            // price < clearingPrice       | clearingPrice == price -------------------------->

            // Account the fully filled checkpoints
            (tokensFilled, refund) = bid.resolve(
                tick.price,
                lastValidCheckpoint.cumulativeMpsPerPrice - startCheckpoint.cumulativeMpsPerPrice,
                lastValidCheckpoint.cumulativeMps - startCheckpoint.cumulativeMps
            );

            /**
             * The tokens sold to bidders of a price (p) is equal to the supply sold
             * proportion of the demand at p of the total demand at or above the clearing price.
             *
             * S_p = S * D_tick / (D_upper + D_tick)
             *
             * Furthermore, the tokens sold to a bidder at price (p) is proportional to their demand of the demand at p.
             *
             * S_b = S_p * D_bid / D_tick
             *
             * Expanding:
             *
             * S_b = (S * D_tick / (D_upper + D_tick)) * D_bid / D_tick
             * S_b = S * D_bid / (D_upper + D_tick)
             *
             * D_upper and D_tick can change over time
             */
            uint256 d_tick = tick.resolveDemand(tickSpacing);
            uint256 d_upper = sumDemandTickUpper.resolve(tick.price, tickSpacing);

            Checkpoint memory finalCheckpoint = upperCheckpoint.transform(endBlock - upperCheckpointBlock, step.mps);
            (uint256 partialTokensFilled, uint256 partialRefund) =
                _partialFill(bid, tick, upperCheckpoint, finalCheckpoint);
            tokensFilled += partialTokensFilled;
            refund += partialRefund;
        } else {
            revert CannotWithdrawBid();
        }

        currency.transfer(bid.owner, refund);

        if (tokensFilled == 0) {
            _deleteBid(bidId);
        } else {
            bid.tokensFilled = tokensFilled;
            bid.withdrawnBlock = uint64(block.number);
            _updateBid(bidId, bid);
        }

        emit BidWithdrawn(bidId, bid.owner);
    }

    function _partialFill(Bid memory bid, Tick memory tick, Checkpoint memory start, Checkpoint memory end)
        internal
        view
        returns (uint256 tokensFilled, uint256 refund)
    {
        uint256 supplySold = end.totalCleared - start.totalCleared;
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
