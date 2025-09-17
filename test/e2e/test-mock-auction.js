const { ethers } = require('hardhat');

async function testMockAuction() {
  console.log('Testing MockAuction creation...');
  
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
  
  // Try to create MockAuction directly
  console.log('Creating MockAuction directly...');
  try {
    const MockAuction = await ethers.getContractFactory('MockAuction');
    const auction = await MockAuction.deploy(
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
    
    console.log('MockAuction created successfully!');
    console.log('Auction address:', await auction.getAddress());
  } catch (error) {
    console.error('MockAuction creation failed:', error.message);
    console.error('Full error:', error);
  }
}

testMockAuction().catch(console.error);
