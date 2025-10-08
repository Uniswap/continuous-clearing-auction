// SPDX-License-Identifier: MIT
/// Inspired by https://github.com/ProjectOpenSea/seaport/blob/main/test/foundry/new/helpers/FuzzGenerators.sol
pragma solidity ^0.8.0;

import {FuzzGeneratorContext, FuzzGeneratorContextLib} from './FuzzGeneratorContextLib.sol';
import {
    ActionSpace,
    AuctionPhaseSpace,
    BidPriceSpace,
    BidSizeSpace,
    CurrencyAmountSpace,
    CurrencyDecimalsSpace,
    CurrencyTypeSpace,
    EmissionDurationSpace,
    EmissionRateSpace,
    ExistingBidsSpace,
    FloorPriceSpace,
    GraduatedSpace,
    NumberOfStepsSpace,
    RemainingSupplySpace,
    SenderSpace,
    SubscriptionStatusSpace,
    TickSpacingSpace,
    TokenDecimalsSpace,
    TotalSupplySpace
} from './FuzzSpaceEnums.sol';
import {LibPRNG} from 'solady/src/utils/LibPRNG.sol';

library TestStateGenerator {
    // TODO(ez):
    // - Generator needs to generate setup the accounts in the test, balances, approvals, etc.
    // - It needs to generate valid auction parameters
}

library AuctionParametersGenerator {
    using LibPRNG for LibPRNG.PRNG;

    function generate(AuctionParametersSpace memory space, FuzzGeneratorContext memory context)
        internal
        pure
        returns (AuctionParametersSpace)
    {
        space.totalSupply = TotalSupplyGenerator.generate(space.totalSupply, context);
        space.floorPrice = FloorPriceGenerator.generate(space.floorPrice, context);
        space.tickSpacing = TickSpacingGenerator.generate(space.tickSpacing, context);
        space.validationHook = ValidationHookGenerator.generate(space.validationHook, context);
        space.tokensRecipient = TokensRecipientGenerator.generate(space.tokensRecipient, context);
        space.fundsRecipient = FundsRecipientGenerator.generate(space.fundsRecipient, context);
        return space;
    }
}

library ValidationHookGenerator {
    function generate(ValidationHookSpace memory validationHook, FuzzGeneratorContext memory context)
        internal
        pure
        returns (IValidationHook)
    {
        if (validationHook == ValidationHookSpace.None) {
            return IValidationHook(address(0));
        } else if (validationHook == ValidationHookSpace.Reverting) {
            return IValidationHook(address(context.validationHookReverting));
        } else if (validationHook == ValidationHookSpace.RevertingWithCustomError) {
            return IValidationHook(address(context.validationHookWithCustomError));
        } else if (validationHook == ValidationHookSpace.OutOfGas) {
            return IValidationHook(address(context.validationHookOutOfGas));
        } else if (validationHook == ValidationHookSpace.Passing) {
            return IValidationHook(address(context.validationHook));
        } else {
            revert('Invalid validation hook');
        }
    }
}

library CurrencyDecimalsGenerator {
    function generate(CurrencyDecimalsSpace memory currencyDecimals, FuzzGeneratorContext memory context)
        internal
        pure
        returns (uint8)
    {
        if (currencyDecimals == CurrencyDecimalsSpace.Low) {
            return 6;
        } else if (currencyDecimals == CurrencyDecimalsSpace.Standard) {
            return 18;
        } else if (currencyDecimals == CurrencyDecimalsSpace.High) {
            return 20; // TODO(ez): is this actually high decimal num? Look at SHIB
        } else {
            revert('Invalid currency decimals');
        }
    }
}

library CurrencyTypeGenerator {
    function generate(CurrencyTypeSpace memory currencyType, FuzzGeneratorContext memory context)
        internal
        pure
        returns (CurrencyTypeSpace)
    {
        if (currencyType == CurrencyTypeSpace.Native) {
            return CurrencyTypeSpace.Native;
        } else if (currencyType == CurrencyTypeSpace.ERC20) {
            return CurrencyTypeSpace.ERC20;
        } else {
            revert('Invalid currency type');
        }
    }
}

library SenderGenerator {
    function generate(SenderSpace memory sender, FuzzGeneratorContext memory context) internal pure returns (address) {
        if (sender == SenderSpace.NewBidder) {
            return context.bob.addr;
        } else if (sender == SenderSpace.RepeatBidder) {
            return context.alice.addr;
        } else {
            revert('Invalid sender');
        }
    }
}

library TokenDecimalsGenerator {
    function generate(TokenDecimalsSpace memory tokenDecimals, FuzzGeneratorContext memory context)
        internal
        pure
        returns (uint8)
    {
        if (tokenDecimals == TokenDecimalsSpace.Low) {
            return 6;
        } else if (tokenDecimals == TokenDecimalsSpace.Standard) {
            return 18;
        } else if (tokenDecimals == TokenDecimalsSpace.High) {
            return 20;
        } else {
            revert('Invalid token decimals');
        }
    }
}

library TotalSupplyGenerator {
    function generate(TotalSupplySpace memory totalSupply, FuzzGeneratorContext memory context)
        internal
        pure
        returns (uint128)
    {
        if (totalSupply == TotalSupplySpace.Low) {
            return 1e6; // One million
        } else if (totalSupply == TotalSupplySpace.High) {
            return 1e12; // One trillion
        } else {
            revert('Invalid total supply');
        }
    }
}
