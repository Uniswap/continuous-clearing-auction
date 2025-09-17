// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// No import needed for this mock

contract MockAuction {
    address public currency;
    address public token;
    address public tokensRecipient;
    address public fundsRecipient;
    uint64 public startBlock;
    uint64 public endBlock;
    uint64 public claimBlock;
    uint24 public graduationThresholdMps;
    uint256 public tickSpacing;
    address public validationHook;
    uint256 public floorPrice;
    
    uint256 public totalCleared;
    uint256 public currencyRaised;
    bool public graduated;
    
    event BidSubmitted(address indexed bidder, uint256 amount, uint256 price);
    event CurrencySwept(address indexed recipient, uint256 amount);
    event TokensSwept(address indexed recipient, uint256 amount);
    
    constructor(
        address _token,
        address _currency,
        address _tokensRecipient,
        address _fundsRecipient,
        uint64 _startBlock,
        uint64 _endBlock,
        uint64 _claimBlock,
        uint24 _graduationThresholdMps,
        uint256 _tickSpacing,
        address _validationHook,
        uint256 _floorPrice
    ) {
        require(_token != address(0), "Token cannot be zero");
        require(_tokensRecipient != address(0), "TokensRecipient cannot be zero");
        require(_fundsRecipient != address(0), "FundsRecipient cannot be zero");
        require(_startBlock > 0, "StartBlock must be > 0");
        require(_endBlock > _startBlock, "EndBlock must be > StartBlock");
        require(_claimBlock >= _endBlock, "ClaimBlock must be >= EndBlock");
        require(_graduationThresholdMps > 0, "GraduationThresholdMps must be > 0");
        require(_tickSpacing > 0, "TickSpacing must be > 0");
        require(_floorPrice > 0, "FloorPrice must be > 0");
        // validationHook can be zero (optional)
        
        // Debug logging
        // Note: In a real contract, we'd use events, but for debugging we'll just continue
        
        token = _token;
        currency = _currency;
        tokensRecipient = _tokensRecipient;
        fundsRecipient = _fundsRecipient;
        startBlock = _startBlock;
        endBlock = _endBlock;
        claimBlock = _claimBlock;
        graduationThresholdMps = _graduationThresholdMps;
        tickSpacing = _tickSpacing;
        validationHook = _validationHook;
        floorPrice = _floorPrice;
    }
    
    function submitBid(uint256 maxPrice, bool exactIn, uint128 amount, address owner, uint256 prevTickPrice, bytes calldata hookData) external payable {
        require(block.number < endBlock, "Auction is over");
        
        // Simple mock logic - just track the bid
        totalCleared += amount;
        currencyRaised += maxPrice;
        
        emit BidSubmitted(owner, amount, maxPrice);
    }
    
    function isGraduated() public view returns (bool) {
        return graduated;
    }
    
    function getTotalCleared() public view returns (uint256) {
        return totalCleared;
    }
    
    function getCurrencyRaised() public view returns (uint256) {
        return currencyRaised;
    }
    
    function sweepCurrency() external {
        require(block.number >= endBlock, "Auction not over");
        require(!graduated, "Already graduated");
        
        graduated = true;
        emit CurrencySwept(fundsRecipient, currencyRaised);
    }
    
    function sweepUnsoldTokens() external {
        require(block.number >= endBlock, "Auction not over");
        
        emit TokensSwept(tokensRecipient, 1000); // Mock amount
    }
}
