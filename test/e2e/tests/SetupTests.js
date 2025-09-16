const { expect } = require('chai');
const { ethers, network } = require('hardhat');
const TestRunner = require('../src/TestRunner');
const AuctionDeployer = require('../src/AuctionDeployer');

describe('Auction Setup Tests', function() {
  let testRunner;
  let deployer;

  before(async function() {
    testRunner = new TestRunner();
    deployer = new AuctionDeployer();
  });

  it('Should validate and deploy setup01', async function() {
    const setupData = testRunner.loadTestInstance('setup', 'setup01.json');
    
    // Validate the setup data
    testRunner.validateSetup(setupData);
    
    // Deploy token
    const token = await deployer.deployToken(setupData.token);
    expect(await token.getAddress()).to.be.properAddress;
    
    // Setup balances
    await deployer.setupBalances(setupData);
    
    // Create auction
    const auction = await deployer.createAuction(setupData, token);
    expect(await auction.getAddress()).to.be.properAddress;
    
    // Verify auction parameters
    const auctionParams = await auction.getAuctionParameters();
    expect(auctionParams.currency).to.equal(setupData.auctionParameters.currency);
    expect(auctionParams.tokensRecipient).to.equal(setupData.auctionParameters.tokensRecipient);
    expect(auctionParams.fundsRecipient).to.equal(setupData.auctionParameters.fundsRecipient);
  });

  it('Should handle invalid setup data', async function() {
    const invalidSetup = {
      env: { startBlock: "21000000" },
      auctionParameters: {
        // Missing required fields
      },
      token: {
        decimals: "18",
        name: "test",
        totalSupply: "100000000000000000000000",
        percentAuctioned: "25.1"
      }
    };

    expect(() => {
      testRunner.validateSetup(invalidSetup);
    }).to.throw('Setup validation failed');
  });

  it('Should calculate auction amount correctly', async function() {
    const setupData = testRunner.loadTestInstance('setup', 'setup01.json');
    const token = await deployer.deployToken(setupData.token);
    
    const auctionAmount = deployer.calculateAuctionAmount(setupData.token, token);
    const expectedAmount = BigInt(setupData.token.totalSupply) * BigInt(251) / BigInt(1000); // 25.1%
    
    expect(auctionAmount).to.equal(expectedAmount);
  });
});
