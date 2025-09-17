// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./MockAuction.sol";
import "hardhat/console.sol";

contract MockAuctionFactory {
    event AuctionCreated(address indexed auction, address indexed token, uint256 amount, bytes configData);
    
    function initializeDistribution(
        address token,
        uint128 amount,
        bytes calldata configData,
        bytes32 salt
    ) external returns (address distributionContract) {
        console.log("MockAuctionFactory: Starting initializeDistribution");
        console.log("Token:", token);
        console.log("Amount:", amount);
        console.log("ConfigData length:", configData.length);
        // console.log("ConfigData (first 100 chars):", string(abi.encodePacked(configData[0:50])));
        
        // Decode the config data to get auction parameters
        console.log("MockAuctionFactory: About to decode configData");
        (
            address currency,
            address tokensRecipient,
            address fundsRecipient,
            uint64 startBlock,
            uint64 endBlock,
            uint64 claimBlock,
            uint24 graduationThresholdMps,
            uint256 tickSpacing,
            address validationHook,
            uint256 floorPrice,
            bytes memory _auctionStepsData
        ) = abi.decode(configData, (address, address, address, uint64, uint64, uint64, uint24, uint256, address, uint256, bytes));
        
        console.log("MockAuctionFactory: Successfully decoded configData");
        console.log("Currency:", currency);
        console.log("StartBlock:", startBlock);
        console.log("EndBlock:", endBlock);
        
        // Debug: Check parameters before creating auction
        require(token != address(0), "Token is zero");
        require(currency != address(0), "Currency is zero");
        require(tokensRecipient != address(0), "TokensRecipient is zero");
        require(fundsRecipient != address(0), "FundsRecipient is zero");
        require(startBlock > 0, "StartBlock must be > 0");
        require(endBlock > startBlock, "EndBlock must be > StartBlock");
        require(claimBlock >= endBlock, "ClaimBlock must be >= EndBlock");
        require(graduationThresholdMps > 0, "GraduationThresholdMps must be > 0");
        require(tickSpacing > 0, "TickSpacing must be > 0");
        require(floorPrice > 0, "FloorPrice must be > 0");
        
        console.log("MockAuctionFactory: All validation checks passed, creating auction");
        // Create the auction
        MockAuction auction = new MockAuction(
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
        
        console.log("MockAuctionFactory: Auction created successfully at", address(auction));
        emit AuctionCreated(address(auction), token, amount, configData);
        
        return address(auction);
    }
}
