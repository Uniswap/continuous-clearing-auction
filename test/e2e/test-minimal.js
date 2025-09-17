const { ethers } = require('hardhat');

async function testMinimal() {
  console.log('Testing minimal auction creation...');
  
  // Deploy a simple token
  const Token = await ethers.getContractFactory('ERC20Mock');
  const token = await Token.deploy('TestToken', 'TEST', 18, '1000000000000000000000');
  console.log('Token deployed:', await token.getAddress());
  
  // Deploy currency token
  const Currency = await ethers.getContractFactory('USDCMock');
  const currency = await Currency.deploy('USD Coin', 'USDC', 6, '1000000000000');
  console.log('Currency deployed:', await currency.getAddress());
  
  // Deploy auction factory
  const Factory = await ethers.getContractFactory('MockAuctionFactory');
  const factory = await Factory.deploy();
  console.log('Factory deployed:', await factory.getAddress());
  
  // Create auction with minimal parameters
  const auctionParams = [
    await currency.getAddress(), // currency
    '0x2222222222222222222222222222222222222222', // tokensRecipient
    '0x3333333333333333333333333333333333333333', // fundsRecipient
    10, // startBlock
    60, // endBlock
    70, // claimBlock
    1000, // graduationThresholdMps
    60, // tickSpacing
    '0x0000000000000000000000000000000000000000', // validationHook
    '1000000000000000', // floorPrice (much smaller)
    '0x', // auctionStepsData
    '0x'  // fundsRecipientData
  ];
  
  const configData = ethers.AbiCoder.defaultAbiCoder().encode(
    ['tuple(address,address,address,uint64,uint64,uint64,uint24,uint256,address,uint256,bytes,bytes)'],
    [auctionParams]
  );
  
  console.log('Creating auction...');
  try {
    // First, let's mine to block 5 to be sure we're in the past
    await ethers.provider.send('hardhat_mine', ['5']);
    console.log('Current block:', await ethers.provider.getBlockNumber());
    
    const tx = await factory.initializeDistribution(
      await token.getAddress(),
      BigInt('1000000000000000000'), // amount (1 token with 18 decimals)
      configData,
      ethers.keccak256(ethers.toUtf8Bytes('test'))
    );
    
    const receipt = await tx.wait();
    console.log('Auction created successfully!');
    console.log('Auction address:', receipt.logs[0].args.auction);
  } catch (error) {
    console.error('Auction creation failed:', error.message);
    console.error('Full error:', error);
    
    // Try to get more details about the revert
    if (error.data) {
      console.error('Error data:', error.data);
    }
  }
}

testMinimal().catch(console.error);
