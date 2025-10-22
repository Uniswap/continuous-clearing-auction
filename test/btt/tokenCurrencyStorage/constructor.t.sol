// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import {BttBase} from 'btt/BttBase.sol';
import {MockTokenCurrencyStorage} from 'btt/mocks/MockTokenCurrencyStorage.sol';
import {ITokenCurrencyStorage} from 'twap-auction/interfaces/ITokenCurrencyStorage.sol';
import {Currency} from 'twap-auction/libraries/CurrencyLibrary.sol';

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

        $token = _token;
        $currency = _currency;
        $tokensRecipient = _tokensRecipient;
        $fundsRecipient = _fundsRecipient;
        $totalSupply = 0;
        $requiredCurrencyRaised = _requiredCurrencyRaised;

        vm.expectRevert(ITokenCurrencyStorage.TotalSupplyIsZero.selector);
        _deployTokenCurrencyStorage();
    }

    modifier whenTotalSupplyGT0(uint128 _totalSupply) {
        $totalSupply = uint128(bound(_totalSupply, 1, type(uint128).max));

        _;
    }

    function test_WhenRequiredRaiseGTUpperBound(uint128 _totalSupply) external whenTotalSupplyGT0(_totalSupply) {
        // it reverts with {RequiredCurrencyRaisedIsTooLarge}

        // With the `_requiredCurrencyRaised` being uint128, it will never hit this case as the following is false:
        // `uint256(type(uint128).max) * FixedPoint96.Q96 > X7_UPPER_BOUND
        // `uint256(type(uint128).max) * 0x1000000000000000000000000 > (type(uint256).max) / 1e7
        // (0x00000000ffffffffffffffffffffffffffffffff000000000000000000000000
        // > 0x000001ad7f29abcaf485787a6520ec08d23699194119a5c37387b71906614310)
        // false
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
    ) external whenTotalSupplyGT0(_totalSupply) whenRequiredRaiseLEUpperBound(_requiredCurrencyRaised) {
        // it reverts with {TokenIsAddressZero}

        $currency = _currency;
        $tokensRecipient = _tokensRecipient;
        $fundsRecipient = _fundsRecipient;
        $token = address(0);

        vm.expectRevert(ITokenCurrencyStorage.TokenIsAddressZero.selector);
        _deployTokenCurrencyStorage();
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
        whenTotalSupplyGT0(_totalSupply)
        whenRequiredRaiseLEUpperBound(_requiredCurrencyRaised)
        whenTokenNEQAddressZero(_token)
    {
        // it reverts with {TokenAndCurrencyCannotBeTheSame}

        $currency = $token;
        $tokensRecipient = _tokensRecipient;
        $fundsRecipient = _fundsRecipient;

        vm.expectRevert(ITokenCurrencyStorage.TokenAndCurrencyCannotBeTheSame.selector);
        _deployTokenCurrencyStorage();
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
        whenTotalSupplyGT0(_totalSupply)
        whenRequiredRaiseLEUpperBound(_requiredCurrencyRaised)
        whenTokenNEQAddressZero(_token)
        whenTokenNEQCurrency(_currency)
    {
        // it reverts with {TokensRecipientIsZero}

        $tokensRecipient = address(0);
        vm.expectRevert(ITokenCurrencyStorage.TokensRecipientIsZero.selector);
        _deployTokenCurrencyStorage();
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
        whenTotalSupplyGT0(_totalSupply)
        whenRequiredRaiseLEUpperBound(_requiredCurrencyRaised)
        whenTokenNEQAddressZero(_token)
        whenTokenNEQCurrency(_currency)
        whenTokensRecipientNEQAddressZero(_tokensRecipient)
    {
        // it reverts with {FundsRecipientIsZero}

        $fundsRecipient = address(0);
        vm.expectRevert(ITokenCurrencyStorage.FundsRecipientIsZero.selector);
        _deployTokenCurrencyStorage();
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
        whenTotalSupplyGT0(_totalSupply)
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

        MockTokenCurrencyStorage tokenCurrencyStorage = _deployTokenCurrencyStorage();

        assertEq(address(tokenCurrencyStorage.token()), $token);
        assertEq(Currency.unwrap(tokenCurrencyStorage.currency()), $currency);
        assertEq(tokenCurrencyStorage.totalSupply(), $totalSupply);
        assertEq(tokenCurrencyStorage.tokensRecipient(), $tokensRecipient);
        assertEq(tokenCurrencyStorage.fundsRecipient(), $fundsRecipient);
    }

    function _deployTokenCurrencyStorage() internal returns (MockTokenCurrencyStorage) {
        return new MockTokenCurrencyStorage(
            $token, $currency, $totalSupply, $tokensRecipient, $fundsRecipient, $requiredCurrencyRaised
        );
    }
}
