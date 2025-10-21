// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import {BttBase} from 'btt/BttBase.sol';
import {MockCheckpointStorage} from 'btt/mocks/MockCheckpointStorage.sol';

import {FixedPointMathLib} from 'solady/utils/FixedPointMathLib.sol';
import {Bid} from 'twap-auction/libraries/BidLib.sol';
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

    function test_WhenDemandEQ0(Bid memory _bid, ValueX7 _cumulativeCurrencyRaisedAtClearingPriceQ96_X7) external {
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
    ) external {
        // it returns the currency spent (bid * raised at price / (demand * remaining mps))
        // it returns the tokens filled (currency spent / max price)

        // Limit values such that end results will not be beyond 256 bits.
        // amount * cumulative * 1e7 * 1e7 * 1e7 <= type(uint256).max

        _cumulativeCurrencyRaisedAtClearingPrice =
            bound(_cumulativeCurrencyRaisedAtClearingPrice, 0, type(uint128).max / 1e14);

        _bid.amountQ96 = bound(_bid.amountQ96, 0, type(uint128).max / ConstantsLib.MPS);
        _bid.maxPrice = bound(_bid.maxPrice, 1, type(uint96).max);
        _bid.startCumulativeMps = uint24(bound(_bid.startCumulativeMps, 0, ConstantsLib.MPS - 1));

        _tickDemandQ96 = bound(_tickDemandQ96, 1, type(uint256).max / ConstantsLib.MPS);

        ValueX7 _cumulativeCurrencyRaisedAtClearingPriceX7 = _cumulativeCurrencyRaisedAtClearingPrice.scaleUpToX7();

        (uint256 tokensFilled, uint256 currencySpent) = mockCheckpointStorage.accountPartiallyFilledCheckpoints(
            _bid, _tickDemandQ96, _cumulativeCurrencyRaisedAtClearingPriceX7
        );

        uint256 left = ConstantsLib.MPS - _bid.startCumulativeMps;

        uint256 scaledCurrencySpent = FixedPointMathLib.fullMulDivUp(
            _bid.amountQ96 * ConstantsLib.MPS,
            ValueX7.unwrap(_cumulativeCurrencyRaisedAtClearingPriceX7),
            _tickDemandQ96 * left
        );

        assertEq(currencySpent, scaledCurrencySpent / ConstantsLib.MPS, 'currency spent');
        assertEq(tokensFilled, scaledCurrencySpent / (_bid.maxPrice * ConstantsLib.MPS), 'tokens filled');
    }
}
