// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./SimpleAuction.sol";
import "hardhat/console.sol";

contract SimpleAuctionFactory {
    event AuctionCreated(address indexed auction, address indexed token, uint256 amount);

    function createAuction(
        address token,
        address currency,
        address tokensRecipient,
        address fundsRecipient,
        uint64 startBlock,
        uint64 endBlock,
        uint64 claimBlock,
        uint24 graduationThresholdMps,
        uint256 tickSpacing,
        address validationHook,
        uint256 floorPrice
    ) external returns (address) {
        console.log("SimpleAuctionFactory: Creating auction");
        console.log("Token:", token);
        console.log("Currency:", currency);
        console.log("StartBlock:", startBlock);
        
        SimpleAuction auction = new SimpleAuction(
            token,
            currency,
            tokensRecipient,
            fundsRecipient,
            startBlock,
            endBlock,
            claimBlock,
            graduationThresholdMps,
            tickSpacing,
            validationHook,
            floorPrice
        );
        
        console.log("SimpleAuctionFactory: Auction created at", address(auction));
        emit AuctionCreated(address(auction), token, 0);
        return address(auction);
    }
}