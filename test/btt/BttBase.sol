// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import {Test} from 'forge-std/Test.sol';
import {VmSafe} from 'forge-std/Vm.sol';

import {Bid} from 'twap-auction/BidStorage.sol';
import {Checkpoint} from 'twap-auction/libraries/CheckpointLib.sol';

import {ValueX7} from 'twap-auction/libraries/ValueX7Lib.sol';

contract BttBase is Test {
    function isCoverage() internal view returns (bool) {
        return vm.isContext(VmSafe.ForgeContext.Coverage);
    }

    function assertEq(Bid memory _bid, Bid memory _bid2) internal pure {
        assertEq(_bid.startBlock, _bid2.startBlock, 'startBlock');
        assertEq(_bid.startCumulativeMps, _bid2.startCumulativeMps, 'startCumulativeMps');
        assertEq(_bid.exitedBlock, _bid2.exitedBlock, 'exitedBlock');
        assertEq(_bid.maxPrice, _bid2.maxPrice, 'maxPrice');
        assertEq(_bid.owner, _bid2.owner, 'owner');
        assertEq(_bid.amountQ96, _bid2.amountQ96, 'amountQ96');
        assertEq(_bid.tokensFilled, _bid2.tokensFilled, 'tokensFilled');
    }

    function assertEq(ValueX7 _valueX7, ValueX7 _valueX72) internal pure {
        assertEq(ValueX7.unwrap(_valueX7), ValueX7.unwrap(_valueX72));
    }

    function assertEq(ValueX7 _valueX7, ValueX7 _valueX72, string memory _err) internal pure {
        assertEq(ValueX7.unwrap(_valueX7), ValueX7.unwrap(_valueX72), _err);
    }

    function assertEq(Checkpoint memory _checkpoint, Checkpoint memory _checkpoint2) internal pure {
        assertEq(_checkpoint.clearingPrice, _checkpoint2.clearingPrice, 'clearingPrice');
        assertEq(_checkpoint.currencyRaisedQ96_X7, _checkpoint2.currencyRaisedQ96_X7, 'currencyRaisedQ96_X7');
        assertEq(
            _checkpoint.currencyRaisedAtClearingPriceQ96_X7,
            _checkpoint2.currencyRaisedAtClearingPriceQ96_X7,
            'currencyRaisedAtClearingPriceQ96_X7'
        );
        assertEq(_checkpoint.cumulativeMpsPerPrice, _checkpoint2.cumulativeMpsPerPrice, 'cumulativeMpsPerPrice');
        assertEq(_checkpoint.cumulativeMps, _checkpoint2.cumulativeMps, 'cumulativeMps');
        assertEq(_checkpoint.prev, _checkpoint2.prev, 'prev');
        assertEq(_checkpoint.next, _checkpoint2.next, 'next');
    }
}
