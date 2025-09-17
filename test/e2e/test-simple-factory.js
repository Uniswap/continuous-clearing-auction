const { ethers } = require('hardhat');

async function testSimpleFactory() {
  console.log('Testing SimpleAuctionFactory...');
  
  // Deploy a simple token
  const Token = await ethers.getContractFactory('ERC20Mock');
  const token = await Token.deploy('TestToken', 'TEST', 18, '1000000000000000000000');
  console.log('Token deployed:', await token.getAddress());
  
  // Deploy currency token
  const Currency = await ethers.getContractFactory('USDCMock');
  const currency = await Currency.deploy('USD Coin', 'USDC', 6, '1000000000000');
  console.log('Currency deployed:', await currency.getAddress());
  
  // Mine to block 5
  await ethers.provider.send('hardhat_mine', ['5']);
  console.log('Current block:', await ethers.provider.getBlockNumber());
  
  // Deploy factory
  const Factory = await ethers.getContractFactory('SimpleAuctionFactory');
  const factory = await Factory.deploy();
  console.log('Factory deployed:', await factory.getAddress());
  
  console.log('Creating auction...');
  try {
    const tx = await factory.createAuction(
      await token.getAddress(), // token
      await currency.getAddress(), // currency
      '0x2222222222222222222222222222222222222222', // tokensRecipient
      '0x3333333333333333333333333333333333333333', // fundsRecipient
      10, // startBlock
      60, // endBlock
      70, // claimBlock
      1000, // graduationThresholdMps
      60, // tickSpacing
      '0x0000000000000000000000000000000000000000', // validationHook
      '1000000000000000' // floorPrice
    );
    
    const receipt = await tx.wait();
    console.log('Auction created successfully!');
    console.log('Auction address:', receipt.logs[0].args.auction);
  } catch (error) {
    console.error('Auction creation failed:', error.message);
    console.error('Full error:', error);
  }
}

testSimpleFactory().catch(console.error);
