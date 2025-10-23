// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import {BttBase} from 'btt/BttBase.sol';
import {MockCheckpointStorage} from 'btt/mocks/MockCheckpointStorage.sol';

import {FixedPointMathLib} from 'solady/utils/FixedPointMathLib.sol';
import {Bid, BidLib} from 'twap-auction/libraries/BidLib.sol';
import {ConstantsLib} from 'twap-auction/libraries/ConstantsLib.sol';
import {FixedPoint96} from 'twap-auction/libraries/FixedPoint96.sol';
import {ValueX7} from 'twap-auction/libraries/ValueX7Lib.sol';
import {ValueX7Lib} from 'twap-auction/libraries/ValueX7Lib.sol';

contract AccountPartiallyFilledCheckpointsTest is BttBase {
    using ValueX7Lib for uint256;

    MockCheckpointStorage public mockCheckpointStorage;

    function setUp() external {
        mockCheckpointStorage = new MockCheckpointStorage();
    }

    function test_WhenDemandEQ0(Bid memory _bid, ValueX7 _cumulativeCurrencyRaisedAtClearingPriceQ96_X7) external view {
        // it returns (0, 0)

        (uint256 tokensFilled, uint256 currencySpent) = mockCheckpointStorage.accountPartiallyFilledCheckpoints(
            _bid, 0, _cumulativeCurrencyRaisedAtClearingPriceQ96_X7
        );

        assertEq(tokensFilled, 0);
        assertEq(currencySpent, 0);
    }

    function test_WhenDemandGT0(
        Bid memory _bid,
        uint256 _tickDemandQ96,
        uint256 _cumulativeCurrencyRaisedAtClearingPrice
    ) external view {
        // it returns the currency spent (bid * raised at price / (demand * remaining mps))
        // it returns the tokens filled (currency spent / max price)

        // Limit values such that end results will not be beyond 256 bits.
        // amountQ96 * 1e7 * cumulativeQ96 * 1e7 / tickDemandQ96 * remainingMps
        // as the amount is part of the demand, amount <= tickDemand, we can "cancel" them (concerning the limits)
        // cumulativeQ96 * 1e14 / remainingMps.  where the worst value for remainingMps would be 1, so we have
        // cumulativeQ96 * 1e14 <= type(uint256).max

        _bid.amountQ96 = bound(_bid.amountQ96, 1, type(uint128).max);
        _bid.maxPrice = bound(_bid.maxPrice, 1, ConstantsLib.MAX_BID_PRICE);
        _bid.startCumulativeMps = uint24(bound(_bid.startCumulativeMps, 0, ConstantsLib.MPS - 1));
        _tickDemandQ96 = bound(_tickDemandQ96, BidLib.toEffectiveAmount(_bid), type(uint256).max / ConstantsLib.MPS);

        _cumulativeCurrencyRaisedAtClearingPrice =
            bound(_cumulativeCurrencyRaisedAtClearingPrice, 0, type(uint256).max / 1e14);

        ValueX7 _cumulativeCurrencyRaisedAtClearingPriceX7 = _cumulativeCurrencyRaisedAtClearingPrice.scaleUpToX7();

        (uint256 tokensFilled, uint256 currencySpent) = mockCheckpointStorage.accountPartiallyFilledCheckpoints(
            _bid, _tickDemandQ96, _cumulativeCurrencyRaisedAtClearingPriceX7
        );

        uint256 currencySpentQ96RoundedUp = FixedPointMathLib.fullMulDivUp(
            _bid.amountQ96 * ConstantsLib.MPS,
            ValueX7.unwrap(_cumulativeCurrencyRaisedAtClearingPriceX7),
            _tickDemandQ96 * (ConstantsLib.MPS - _bid.startCumulativeMps)
        );

        uint256 tokensFilledRoundedDown =
            FixedPointMathLib.fullMulDiv(
                    _bid.amountQ96 * ConstantsLib.MPS,
                    ValueX7.unwrap(_cumulativeCurrencyRaisedAtClearingPriceX7),
                    _tickDemandQ96 * (ConstantsLib.MPS - _bid.startCumulativeMps)
                ) / ConstantsLib.MPS / _bid.maxPrice;

        assertEq(currencySpent, currencySpentQ96RoundedUp / ConstantsLib.MPS, 'currency spent');
        assertEq(tokensFilled, tokensFilledRoundedDown, 'tokens filled');
    }
}
