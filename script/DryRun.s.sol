// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script} from 'forge-std/Script.sol';
import {console2} from 'forge-std/console2.sol';
import {ERC20Mock} from 'openzeppelin-contracts/contracts/mocks/token/ERC20Mock.sol';
import {FixedPointMathLib} from 'solady/utils/FixedPointMathLib.sol';
import {AuctionParameters, IContinuousClearingAuction} from 'src/interfaces/IContinuousClearingAuction.sol';
import {IContinuousClearingAuctionFactory} from 'src/interfaces/IContinuousClearingAuctionFactory.sol';
import {FixedPoint96} from 'src/libraries/FixedPoint96.sol';
import {AuctionStepsBuilder} from 'test/utils/AuctionStepsBuilder.sol';

contract DryRunScript is Script {
    using AuctionStepsBuilder for bytes;

    function run() public {
        vm.startBroadcast();

        ERC20Mock token = new ERC20Mock();
        token.mint(msg.sender, type(uint256).max);

        vm.stopBroadcast();

        vm.startBroadcast();

        IContinuousClearingAuctionFactory factory =
            IContinuousClearingAuctionFactory(0xcca110c1136B93Eb113cceae3C25e52E180B32C9);
        require(address(factory).code.length > 0, 'Factory is not deployed');

        AuctionParameters memory parameters = AuctionParameters({
            currency: address(0), // ETH
            tokensRecipient: msg.sender,
            fundsRecipient: msg.sender,
            startBlock: uint64(block.number),
            endBlock: uint64(block.number + 50),
            claimBlock: uint64(block.number + 50),
            tickSpacing: 79_228_162_514_264_337_593_543_950_336,
            validationHook: address(0),
            floorPrice: 79_228_162_514_264_337_593_543_950_336, // 1:1000 token:currency ratio
            requiredCurrencyRaised: 0,
            auctionStepsData: AuctionStepsBuilder.init().addStep(200e3, 50) // 10% for 10 blocks
        });

        uint128 totalSupply = 1000e18;

        IContinuousClearingAuction auction = IContinuousClearingAuction(
            address(factory.initializeDistribution(address(token), totalSupply, abi.encode(parameters), bytes32(0)))
        );
        console2.log('Auction created at', address(auction));
        token.transfer(address(auction), totalSupply);
        auction.onTokensReceived();

        // burn the rest of the tokens
        token.burn(msg.sender, token.balanceOf(msg.sender));

        vm.stopBroadcast();
    }

    function submitBid() public {
        address auctionAddress = vm.envAddress('AUCTION_ADDRESS');
        vm.startBroadcast();
        IContinuousClearingAuction auction = IContinuousClearingAuction(auctionAddress);
        uint256 maxPrice = 2 * uint256(auction.floorPrice());
        uint128 amount = uint128(FixedPointMathLib.fullMulDivUp(1e10, maxPrice, FixedPoint96.Q96));
        uint256 bidId = auction.submitBid{value: amount}(maxPrice, amount, msg.sender, bytes(''));
        console2.log('Bid submitted at', bidId);
        vm.stopBroadcast();
    }

    // Assumes that the bid is fully filled
    function exitBidAndClaimTokens() public {
        address auctionAddress = vm.envAddress('AUCTION_ADDRESS');
        vm.startBroadcast();
        IContinuousClearingAuction auction = IContinuousClearingAuction(auctionAddress);
        auction.exitBid(0);
        console2.log('Bid exited');
        auction.claimTokens(0);
        console2.log('Tokens claimed');
        vm.stopBroadcast();
    }
}
