// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import {BttBase} from 'btt/BttBase.sol';
import {MockAuctionStorage} from 'btt/mocks/MockAuctionStorage.sol';
import {IAuctionStorage} from 'continuous-clearing-auction/interfaces/IAuctionStorage.sol';
import {ConstantsLib} from 'continuous-clearing-auction/libraries/ConstantsLib.sol';
import {Currency} from 'continuous-clearing-auction/libraries/CurrencyLibrary.sol';

contract ConstructorTest is BttBase {
    address $token;
    address $currency;
    uint128 $totalSupply;
    address $tokensRecipient;
    address $fundsRecipient;
    uint128 $requiredCurrencyRaised;

    function test_WhenTotalSupplyEQ0(
        address _token,
        address _currency,
        address _tokensRecipient,
        address _fundsRecipient,
        uint128 _requiredCurrencyRaised
    ) external {
        // it reverts with {TotalSupplyIsZero}

        vm.assume(_token != address(0)); // this check preceeds the TotalSupplyIsZero check
        vm.assume(_token != _currency); // this check preceeds the TotalSupplyIsZero check

        $token = _token;
        $currency = _currency;
        $tokensRecipient = _tokensRecipient;
        $fundsRecipient = _fundsRecipient;
        $totalSupply = 0;
        $requiredCurrencyRaised = _requiredCurrencyRaised;

        vm.expectRevert(IAuctionStorage.TotalSupplyIsZero.selector);
        _deployAuctionStorage();
    }

    function test_WhenTotalSupplyGTMax(uint128 _totalSupply) external {
        // it reverts with {TotalSupplyIsTooLarge}

        // Prevent early reverts
        $token = address(1);
        $currency = address(2);

        $totalSupply = uint128(_bound(_totalSupply, ConstantsLib.MAX_TOTAL_SUPPLY + 1, type(uint128).max));

        vm.expectRevert(IAuctionStorage.TotalSupplyIsTooLarge.selector);
        _deployAuctionStorage();
    }

    modifier whenTotalSupplyGT0AndLTEMax(uint128 _totalSupply) {
        $totalSupply = uint128(_bound(_totalSupply, 1, ConstantsLib.MAX_TOTAL_SUPPLY));

        _;
    }

    modifier whenRequiredRaiseLEUpperBound(uint128 _requiredCurrencyRaised) {
        $requiredCurrencyRaised = _requiredCurrencyRaised;
        _;
    }

    function test_WhenTokenEQAddressZero(
        address _currency,
        uint128 _totalSupply,
        address _tokensRecipient,
        address _fundsRecipient,
        uint128 _requiredCurrencyRaised
    ) external whenTotalSupplyGT0AndLTEMax(_totalSupply) whenRequiredRaiseLEUpperBound(_requiredCurrencyRaised) {
        // it reverts with {TokenIsAddressZero}

        $currency = _currency;
        $tokensRecipient = _tokensRecipient;
        $fundsRecipient = _fundsRecipient;
        $token = address(0);

        vm.expectRevert(IAuctionStorage.TokenIsAddressZero.selector);
        _deployAuctionStorage();
    }

    modifier whenTokenNEQAddressZero(address _token) {
        vm.assume(_token != address(0));
        $token = _token;
        _;
    }

    function test_WhenTokenEQCurrency(
        address _token,
        uint128 _totalSupply,
        address _tokensRecipient,
        address _fundsRecipient,
        uint128 _requiredCurrencyRaised
    )
        external
        whenTotalSupplyGT0AndLTEMax(_totalSupply)
        whenRequiredRaiseLEUpperBound(_requiredCurrencyRaised)
        whenTokenNEQAddressZero(_token)
    {
        // it reverts with {TokenAndCurrencyCannotBeTheSame}

        $currency = $token;
        $tokensRecipient = _tokensRecipient;
        $fundsRecipient = _fundsRecipient;

        vm.expectRevert(IAuctionStorage.TokenAndCurrencyCannotBeTheSame.selector);
        _deployAuctionStorage();
    }

    modifier whenTokenNEQCurrency(address _currency) {
        vm.assume(_currency != $token);
        $currency = _currency;
        _;
    }

    function test_WhenTokensRecipientEQAddressZero(
        address _token,
        uint128 _totalSupply,
        address _currency,
        uint128 _requiredCurrencyRaised
    )
        external
        whenTotalSupplyGT0AndLTEMax(_totalSupply)
        whenRequiredRaiseLEUpperBound(_requiredCurrencyRaised)
        whenTokenNEQAddressZero(_token)
        whenTokenNEQCurrency(_currency)
    {
        // it reverts with {TokensRecipientIsZero}

        $tokensRecipient = address(0);
        vm.expectRevert(IAuctionStorage.TokensRecipientIsZero.selector);
        _deployAuctionStorage();
    }

    modifier whenTokensRecipientNEQAddressZero(address _tokensRecipient) {
        vm.assume(_tokensRecipient != address(0));
        $tokensRecipient = _tokensRecipient;
        _;
    }

    function test_WhenFundsRecipientEQAddressZero(
        address _token,
        uint128 _totalSupply,
        address _currency,
        address _tokensRecipient,
        uint128 _requiredCurrencyRaised
    )
        external
        whenTotalSupplyGT0AndLTEMax(_totalSupply)
        whenRequiredRaiseLEUpperBound(_requiredCurrencyRaised)
        whenTokenNEQAddressZero(_token)
        whenTokenNEQCurrency(_currency)
        whenTokensRecipientNEQAddressZero(_tokensRecipient)
    {
        // it reverts with {FundsRecipientIsZero}

        $fundsRecipient = address(0);
        vm.expectRevert(IAuctionStorage.FundsRecipientIsZero.selector);
        _deployAuctionStorage();
    }

    function test_WhenFundsRecipientNEQAddressZero(
        address _token,
        uint128 _totalSupply,
        address _currency,
        address _tokensRecipient,
        address _fundsRecipient,
        uint128 _requiredCurrencyRaised
    )
        external
        whenTotalSupplyGT0AndLTEMax(_totalSupply)
        whenRequiredRaiseLEUpperBound(_requiredCurrencyRaised)
        whenTokenNEQAddressZero(_token)
        whenTokenNEQCurrency(_currency)
        whenTokensRecipientNEQAddressZero(_tokensRecipient)
    {
        // it writes token
        // it writes currency
        // it writes totalSupply
        // it writes totalSupply as X7X7
        // it writes tokens recipient
        // it writes currency recipient

        vm.assume(_fundsRecipient != address(0));
        $fundsRecipient = _fundsRecipient;

        MockAuctionStorage auctionStorage = _deployAuctionStorage();

        assertEq(auctionStorage.token(), address($token));
        assertEq(auctionStorage.currency(), address($currency));
        assertEq(auctionStorage.totalSupply(), $totalSupply);
        assertEq(auctionStorage.tokensRecipient(), $tokensRecipient);
        assertEq(auctionStorage.fundsRecipient(), $fundsRecipient);
    }

    function _deployAuctionStorage() internal returns (MockAuctionStorage) {
        return new MockAuctionStorage(
            $token, $currency, $totalSupply, $tokensRecipient, $fundsRecipient, $requiredCurrencyRaised, address(0)
        );
    }
}
