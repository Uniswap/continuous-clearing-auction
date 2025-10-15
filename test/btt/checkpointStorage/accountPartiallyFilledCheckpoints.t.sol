// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import {BttBase} from 'btt/BttBase.sol';
import {MockCheckpointStorage} from 'btt/mocks/MockCheckpointStorage.sol';

import {FixedPointMathLib} from 'solady/utils/FixedPointMathLib.sol';
import {Bid} from 'twap-auction/libraries/BidLib.sol';
import {ConstantsLib} from 'twap-auction/libraries/ConstantsLib.sol';
import {FixedPoint96} from 'twap-auction/libraries/FixedPoint96.sol';
import {ValueX7} from 'twap-auction/libraries/ValueX7Lib.sol';

contract AccountPartiallyFilledCheckpointsTest is BttBase {
    MockCheckpointStorage public mockCheckpointStorage;

    function setUp() external {
        mockCheckpointStorage = new MockCheckpointStorage();
    }

    function test_WhenDemandEQ0(Bid memory _bid, ValueX7 _cumulativeCurrencyRaisedAtClearingPriceQ96_X7) external {
        // it returns (0, 0)

        (uint256 tokensFilled, uint256 currencySpent) = mockCheckpointStorage.accountPartiallyFilledCheckpoints(
            _bid, 0, _cumulativeCurrencyRaisedAtClearingPriceQ96_X7
        );

        assertEq(tokensFilled, 0);
        assertEq(currencySpent, 0);
    }

    function test_WhenDemandGT0(Bid memory _bid, uint256 _tickDemandQ96, uint256 _cumulativeCurrencyRaisedAtClearingPrice)
        external
    {
        // it returns the currency spent (bid * raised at price / (demand * remaining mps))
        // it returns the tokens filled (currency spent / max price)

        // Limit values such that end results will not be beyond 256 bits.

        _cumulativeCurrencyRaisedAtClearingPrice =
            bound(_cumulativeCurrencyRaisedAtClearingPrice, FixedPoint96.Q96, type(uint128).max);

        _bid.amountQ96 = bound(_bid.amountQ96, 0, type(uint128).max / 1e7);
        
        // TODO(md): check this bound
        _tickDemandQ96 = bound(_tickDemandQ96, 1, type(uint256).max / ConstantsLib.MPS);

        _bid.startCumulativeMps = uint24(bound(_bid.startCumulativeMps, 0, ConstantsLib.MPS - 1));
        _bid.maxPrice = bound(_bid.maxPrice, FixedPoint96.Q96, type(uint256).max);

        (uint256 tokensFilled, uint256 currencySpent) = mockCheckpointStorage.accountPartiallyFilledCheckpoints(
            _bid, _tickDemandQ96, ValueX7.wrap(_cumulativeCurrencyRaisedAtClearingPrice)
        );

        uint256 left = ConstantsLib.MPS - _bid.startCumulativeMps;

        uint256 scaledCurrencySpent = FixedPointMathLib.fullMulDivUp(
            _bid.amountQ96 * 1e7, _cumulativeCurrencyRaisedAtClearingPrice, _tickDemandQ96 * left
        );
        assertEq(currencySpent, scaledCurrencySpent / 1e7);
        assertEq(tokensFilled, FixedPointMathLib.fullMulDiv(scaledCurrencySpent, FixedPoint96.Q96, _bid.maxPrice) / 1e7);

        // Execute without up and downscaling. Ensure we are very close, allow off by one.
        uint256 directCurrencySpent =
            FixedPointMathLib.fullMulDivUp(_bid.amountQ96, _cumulativeCurrencyRaisedAtClearingPrice, _tickDemandQ96 * left);
        assertApproxEqAbs(currencySpent, directCurrencySpent, 1);
        assertApproxEqAbs(
            tokensFilled, FixedPointMathLib.fullMulDiv(directCurrencySpent, FixedPoint96.Q96, _bid.maxPrice), 1
        );

        // Directly without the full mul. Requires smaller values
        uint256 rawCurrencySpent = (_bid.amountQ96 * _cumulativeCurrencyRaisedAtClearingPrice) / (_tickDemandQ96 * left);
        assertApproxEqAbs(currencySpent, rawCurrencySpent, 1);

        // Not executing this one outside of the full mul as the mul with Q96 limits us to a product in uint160
        // for the currency spent. Which leads each component in the 80'ies, which is just too small, and I would rather
        // test more widely
        // assertApproxEqAbs(tokensFilled, rawCurrencySpent * FixedPoint96.Q96 / _bid.maxPrice, 1, 'tokens filled');
    }
}
