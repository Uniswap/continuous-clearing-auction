// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Auction} from '../../src/Auction.sol';
import {AuctionFactory} from '../../src/AuctionFactory.sol';
import {Tick} from '../../src/TickStorage.sol';
import {AuctionParameters, IAuction} from '../../src/interfaces/IAuction.sol';
import {ITickStorage} from '../../src/interfaces/ITickStorage.sol';
import {Demand} from '../../src/libraries/DemandLib.sol';
import {FixedPoint96} from '../../src/libraries/FixedPoint96.sol';
import {AuctionParamsBuilder} from './AuctionParamsBuilder.sol';
import {AuctionStepsBuilder} from './AuctionStepsBuilder.sol';
import {TokenHandler} from './TokenHandler.sol';
import {Test} from 'forge-std/Test.sol';
import {ERC20Mock} from 'openzeppelin-contracts/contracts/mocks/token/ERC20Mock.sol';

/// @notice Handler contract for setting up an auction
abstract contract AuctionBaseTest is TokenHandler, Test {
    using AuctionParamsBuilder for AuctionParameters;
    using AuctionStepsBuilder for bytes;

    Auction public auction;
    AuctionFactory public factory;

    uint256 public constant AUCTION_DURATION = 100;
    uint256 public constant TICK_SPACING = 100;
    uint256 public constant FLOOR_PRICE = 1000 << FixedPoint96.RESOLUTION;
    uint256 public constant TOTAL_SUPPLY = 1000e18;

    address public alice;
    address public tokensRecipient;
    address public fundsRecipient;

    function setUpAuction() public {
        setUpTokens();

        factory = new AuctionFactory();

        alice = makeAddr('alice');
        tokensRecipient = makeAddr('tokensRecipient');
        fundsRecipient = makeAddr('fundsRecipient');

        bytes memory auctionStepsData = AuctionStepsBuilder.init().addStep(100e3, 50).addStep(100e3, 50);
        AuctionParameters memory params = AuctionParamsBuilder.init().withCurrency(ETH_SENTINEL).withFloorPrice(
            FLOOR_PRICE
        ).withTickSpacing(TICK_SPACING).withValidationHook(address(0)).withTokensRecipient(tokensRecipient)
            .withFundsRecipient(fundsRecipient).withStartBlock(block.number).withEndBlock(block.number + AUCTION_DURATION)
            .withClaimBlock(block.number + AUCTION_DURATION).withAuctionStepsData(auctionStepsData);

        auction = setUpAuctionWithFactory(token, TOTAL_SUPPLY, abi.encode(params), bytes32(0));
    }

    function setUpAuctionWithFactory(ERC20Mock _token, uint256 amount, bytes memory configData, bytes32 salt)
        public
        returns (Auction)
    {
        (address[] memory addresses, uint256[] memory amounts) =
            factory.getAddressesAndAmounts(address(_token), amount, configData, salt);
        _token.mint(addresses[0], amounts[0]);
        // Expect the floor price tick to be initialized
        vm.expectEmit(true, true, true, true);
        emit ITickStorage.TickInitialized(tickNumberToPriceX96(1));
        factory.initializeDistribution(address(_token), amount, configData, salt);
        return Auction(payable(addresses[0]));
    }

    /// @dev Helper function to convert a tick number to a priceX96
    function tickNumberToPriceX96(uint256 tickNumber) internal pure returns (uint256) {
        return ((FLOOR_PRICE >> FixedPoint96.RESOLUTION) + (tickNumber - 1) * TICK_SPACING) << FixedPoint96.RESOLUTION;
    }

    /// @notice Helper function to return the tick at the given price
    function getTick(uint256 price) public view returns (Tick memory) {
        (uint256 next, Demand memory demand) = auction.ticks(price);
        return Tick({next: next, demand: demand});
    }
}
