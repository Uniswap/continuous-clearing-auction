// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

import {TickMath} from 'v4-core/libraries/TickMath.sol';
import {AuctionStepStorage} from './AuctionStepStorage.sol';
import {AuctionParameters} from './Base.sol';
import {Checkpoint, CheckpointStorage} from './CheckpointStorage.sol';
import {BidStorage} from './BidStorage.sol';
import {PermitSingleForwarder} from './PermitSingleForwarder.sol';
import {TickStorage, TickInfo} from './TickStorage.sol';
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
    /// @notice An optional hook to be called before a bid is registered
    IValidationHook public immutable validationHook;
    /// @notice The starting price of the auction
    uint160 public immutable floorPriceX96;

    /// @notice Sum of all demand at or above nextInitializedTick for `currency` (exactIn)
    uint256 public sumCurrencyDemandAtNextInitializedTick;
    /// @notice Sum of all demand at or above nextInitializedTick for `token` (exactOut)
    uint256 public sumTokenDemandAtNextInitializedTick;

    address public constant PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;

    constructor(address _token, uint256 _totalSupply, AuctionParameters memory _parameters)
        AuctionStepStorage(_parameters.auctionStepsData, _parameters.startBlock, _parameters.endBlock)
        TickStorage(_parameters.tickSpacing)
        PermitSingleForwarder(IAllowanceTransfer(PERMIT2))
    {
        currency = Currency.wrap(_parameters.currency);
        token = IERC20Minimal(_token);
        totalSupply = _totalSupply;
        tokensRecipient = _parameters.tokensRecipient;
        fundsRecipient = _parameters.fundsRecipient;
        claimBlock = _parameters.claimBlock;
        validationHook = IValidationHook(_parameters.validationHook);
        floorPriceX96 = _parameters.floorPriceX96;
        // Initialize a tick for the floor price
        _initializeTick(floorPriceX96);

        if (totalSupply == 0) revert TotalSupplyIsZero();
        if (floorPriceX96 == 0) revert FloorPriceIsZero();
        if (claimBlock < endBlock) revert ClaimBlockIsBeforeEndBlock();
        if (fundsRecipient == address(0)) revert FundsRecipientIsZero();
    }

    /// @inheritdoc IDistributionContract
    function onTokensReceived(address _token, uint256 _amount) external view {
        if (_token != address(token)) revert IDistributionContract__InvalidToken();
        if (_amount != totalSupply) revert IDistributionContract__InvalidAmount();
        if (token.balanceOf(address(this)) != _amount) revert IDistributionContract__InvalidAmountReceived();
    }

    function clearingPrice() public view returns (uint160) {
        return latestCheckpoint().clearingPriceX96;
    }

    /// @notice Resolve the token demand at `nextInitializedTick`
    /// @dev This function sums demands from both exactIn and exactOut bids by resolving the exactIn demand at the `nextInitializedTick` price
    ///      and adding all exactOut demand at or above `nextInitializedTick`.
    function _resolvedTokenDemandNextInitializedTick() internal view returns (uint256) {
        return (sumCurrencyDemandAtNextInitializedTick * tickSpacing / TickMath.getSqrtPriceAtTick(nextInitializedTick)) + sumTokenDemandAtNextInitializedTick;
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
            if (_checkpoint.clearingPriceX96 > 0) {
                uint24 deltaMps = uint24(step.mps * delta);
                _cumulativeMps += deltaMps;
                _totalCleared += _checkpoint.blockCleared * delta;
                _cumulativeMpsPerPrice += uint256(deltaMps).fullMulDiv(BidLib.PRECISION, _checkpoint.clearingPriceX96);
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
        uint256 aggregateDemand = _resolvedTokenDemandNextInitializedTick().applyMps(step.mps);

        int24 i = nextInitializedTick;
        uint256 deltaX;
        uint256 deltaY;
        while (aggregateDemand >= resolvedSupply) {
            (int24 next, bool initialized) = _nextGreaterInitializedTick(i);
            require(initialized, "DEBUG: No initialized tick found");

            // Subtract the demand at the old nextInitializedTick as it has been outbid
            TickInfo memory tickInfo = _getTickInfo(i);
            deltaX += tickInfo.sumCurrencyDemand;
            deltaY += tickInfo.sumTokenDemand;

            sumCurrencyDemandAtNextInitializedTick -= tickInfo.sumCurrencyDemand;
            sumTokenDemandAtNextInitializedTick -= tickInfo.sumTokenDemand;

            aggregateDemand = _resolvedTokenDemandNextInitializedTick().applyMps(step.mps);

            // Advance to the next discovered tick
            i = next;
        }
        // Update the next initialized tick
        nextInitializedTick = i;

        uint160 _newClearingPriceX96;
        // Not enough demand to clear at nextInitializedTick, must be between nextInitializedTick and the tick below it
        if (aggregateDemand < resolvedSupply && aggregateDemand > 0) {
            // Find the clearing price between the tickLower and nextInitializedTick
            _newClearingPriceX96 = (resolvedSupply - sumTokenDemandAtNextInitializedTick.applyMps(step.mps)) / (sumCurrencyDemandAtNextInitializedTick.applyMps(step.mps));
            // Round clearingPrice down to the nearest tickSpacing
            _newClearingPriceX96 -= (_newClearingPriceX96 % tickSpacing);
        } else {
            _newClearingPriceX96 = TickMath.getSqrtPriceAtTick(i);
        }

        // If the clearing price is below the floorPrice, set it to the floorPrice
        if (_newClearingPriceX96 <= floorPriceX96) {
            _newClearingPriceX96 = floorPriceX96;
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
            _cumulativeMpsPerPrice + (uint256(mpsSinceLastCheckpoint).fullMulDiv(BidLib.PRECISION, _newClearingPriceX96));

        _insertCheckpoint(
            Checkpoint({
                clearingPriceX96: _newClearingPriceX96,
                blockCleared: _newClearingPriceX96 < floorPriceX96 ? aggregateDemand : resolvedSupply,
                totalCleared: _totalCleared,
                cumulativeMps: _cumulativeMps,
                cumulativeMpsPerPrice: newCumulativeMpsPerPrice,
                prev: _lastCheckpointedBlock
            })
        );

        emit CheckpointUpdated(block.number, _newClearingPriceX96, _totalCleared, _cumulativeMps);
    }

    function _submitBid(
        uint160 maxSqrtPriceX96,
        bool exactIn,
        uint256 amount,
        address owner,
        bytes calldata hookData
    ) internal {
        // First bid in a block updates the clearing price
        checkpoint();

        int24 tick = _initializeTick(maxSqrtPriceX96);

        Bid memory bid = Bid({
            exactIn: exactIn,
            startBlock: uint64(block.number),
            withdrawnBlock: 0,
            tick: tick,
            amount: amount,
            owner: owner,
            tokensFilled: 0
        });

        if (address(validationHook) != address(0)) {
            validationHook.validate(bid, hookData);
        }

        BidLib.validate(maxSqrtPriceX96, floorPriceX96, tickSpacing);
        _updateTickInfo(tick, bid);
        uint256 bidId = _createBid(bid);

        if (bid.exactIn) {
            sumCurrencyDemandAtNextInitializedTick += bid.amount;
        } else {
            sumTokenDemandAtNextInitializedTick += bid.amount;
        }

        emit BidSubmitted(bidId, owner, maxSqrtPriceX96, bid.exactIn, bid.amount);
    }

    /// @inheritdoc IAuction
    function submitBid(
        uint160 maxSqrtPriceX96,
        bool exactIn,
        uint256 amount,
        address owner,
        bytes calldata hookData
    ) external payable {
        // sqrt(price) = sqrt(y/x)
        // (sqrt(price) * sqrt(price)) / x = y
        uint256 resolvedAmount = exactIn ? amount : uint256(maxSqrtPriceX96).fullMulDivUp(uint256(maxSqrtPriceX96), amount);
        if (currency.isAddressZero()) {
            if (msg.value != resolvedAmount) revert InvalidAmount();
        } else {
            SafeTransferLib.permit2TransferFrom(Currency.unwrap(currency), msg.sender, address(this), resolvedAmount);
        }
        _submitBid(maxSqrtPriceX96, exactIn, amount, owner, hookData);
    }

    /// @inheritdoc IAuction
    function withdrawBid(uint256 bidId, uint256 upperCheckpointBlock) external {
        Bid memory bid = _getBid(bidId);
        uint160 maxSqrtPriceX96 = TickMath.getSqrtPriceAtTick(bid.tick);
        if (bid.owner != msg.sender) revert NotBidOwner();
        if (bid.withdrawnBlock != 0) revert BidAlreadyWithdrawn();

        // Can only withdraw if the bid is below the clearing price
        if (maxSqrtPriceX96 >= clearingPrice()) revert CannotWithdrawBid();

        // Require that the upperCheckpoint is the checkpoint immediately after the last active checkpoint for the bid
        Checkpoint memory upperCheckpoint = _getCheckpoint(upperCheckpointBlock);
        Checkpoint memory lastValidCheckpoint = _getCheckpoint(upperCheckpoint.prev);

        if (upperCheckpoint.clearingPriceX96 < maxSqrtPriceX96 || lastValidCheckpoint.clearingPriceX96 >= maxSqrtPriceX96) {
            revert InvalidCheckpointHint();
        }

        // Starting checkpoint must exist because we checkpoint on bid submission
        Checkpoint memory startCheckpoint = _getCheckpoint(bid.startBlock);

        (uint256 tokensFilled, uint256 refund) = bid.resolve(
            maxSqrtPriceX96,
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
