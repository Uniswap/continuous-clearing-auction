const { ethers } = require('hardhat');

class AuctionDeployer {
  constructor() {
    this.auctionFactory = null;
    this.auction = null;
    this.token = null;
    this.currency = null;
  }

  async deployToken(tokenConfig) {
    const Token = await ethers.getContractFactory('ERC20Mock');
    this.token = await Token.deploy(
      tokenConfig.name,
      tokenConfig.name,
      tokenConfig.decimals,
      tokenConfig.totalSupply
    );
    return this.token;
  }

  async deployAuctionFactory() {
    const AuctionFactory = await ethers.getContractFactory('AuctionFactory');
    this.auctionFactory = await AuctionFactory.deploy();
    return this.auctionFactory;
  }

  async createAuction(setupData, token) {
    if (!this.auctionFactory) {
      await this.deployAuctionFactory();
    }

    const auctionParams = this.buildAuctionParameters(setupData);
    const auctionAmount = this.calculateAuctionAmount(setupData.token, token);
    
    const configData = ethers.AbiCoder.defaultAbiCoder().encode(
      ['tuple(address,address,address,uint64,uint64,uint64,uint24,uint256,address,uint256,bytes,bytes)'],
      [auctionParams]
    );

    const tx = await this.auctionFactory.initializeDistribution(
      await token.getAddress(),
      auctionAmount,
      configData,
      ethers.keccak256(ethers.toUtf8Bytes('test'))
    );

    const receipt = await tx.wait();
    const auctionAddress = receipt.logs[0].args.distributionContract;
    
    this.auction = await ethers.getContractAt('Auction', auctionAddress);
    return this.auction;
  }

  buildAuctionParameters(setupData) {
    const { auctionParameters, env } = setupData;
    const startBlock = BigInt(env.startBlock) + BigInt(auctionParameters.startOffsetBlocks);
    const endBlock = startBlock + BigInt(auctionParameters.auctionDurationBlocks);
    const claimBlock = endBlock + BigInt(auctionParameters.claimDelayBlocks);

    return [
      auctionParameters.currency,
      auctionParameters.tokensRecipient,
      auctionParameters.fundsRecipient,
      startBlock,
      endBlock,
      claimBlock,
      auctionParameters.graduationThresholdMps,
      auctionParameters.tickSpacing,
      auctionParameters.validationHook,
      auctionParameters.floorPrice,
      '0x', // auctionStepsData
      '0x'  // fundsRecipientData
    ];
  }

  calculateAuctionAmount(tokenConfig, token) {
    const totalSupply = BigInt(tokenConfig.totalSupply);
    const percentAuctioned = parseFloat(tokenConfig.percentAuctioned);
    return BigInt(Math.floor(Number(totalSupply) * percentAuctioned / 100));
  }

  async setupBalances(setupData) {
    const { env } = setupData;
    if (!env.balances) return;

    for (const balance of env.balances) {
      const signer = await ethers.getImpersonatedSigner(balance.address);
      await ethers.provider.send('hardhat_setBalance', [
        balance.address,
        balance.amount
      ]);
    }
  }
}

module.exports = AuctionDeployer;
