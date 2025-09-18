import { SetupData } from './SchemaValidator';

export interface TokenConfig {
  name: string;
  decimals: string;
  totalSupply: string;
  percentAuctioned: string;
}

export interface BalanceItem {
  address: string;
  token: string;
  amount: string;
}

export class AuctionDeployer {
  private hre: any;
  private ethers: any;
  private auctionFactory: any = null;
  private auction: any = null;
  private tokens: Map<string, any> = new Map(); // Map of token name -> contract instance

  constructor(hre: any) {
    this.hre = hre;
    this.ethers = hre.ethers;
  }

  async deployAdditionalTokens(additionalTokens: TokenConfig[]): Promise<void> {
    console.log('   🪙 Deploying additional tokens...');
    
    for (const tokenConfig of additionalTokens) {
      const Token = await this.ethers.getContractFactory('WorkingCustomMockToken');
      const token = await Token.deploy(
        tokenConfig.name,
        tokenConfig.name.substring(0, Math.min(4, tokenConfig.name.length)).toUpperCase(), // Use first 4 chars as symbol
        parseInt(tokenConfig.decimals),
        tokenConfig.totalSupply || '0'
      );
      
      this.tokens.set(tokenConfig.name, token);
      console.log(`   ✅ Deployed ${tokenConfig.name}: ${await token.getAddress()}`);
    }
  }

  getTokenByName(tokenName: string): any {
    return this.tokens.get(tokenName);
  }

  async getTokenAddress(tokenName: string): Promise<string | null> {
    const token = this.tokens.get(tokenName);
    return token ? await token.getAddress() : null;
  }

  async deployAuctionFactory(): Promise<any> {
    const AuctionFactory = await this.ethers.getContractFactory('AuctionFactory');
    this.auctionFactory = await AuctionFactory.deploy();
    return this.auctionFactory!;
  }

  async createAuction(setupData: SetupData): Promise<any> {
    if (!this.auctionFactory) {
      await this.deployAuctionFactory();
    }

    // TODO: Implement environment configuration
    // Should handle: chainId, blockTimeSec, blockGasLimit, txGasLimit, baseFeePerGasWei
    // Should handle: fork configuration (rpcUrl, blockNumber)

    // Deploy additional tokens
    await this.deployAdditionalTokens(setupData.additionalTokens);

    // Get the auctioned token and currency
    const auctionedToken = this.getTokenByName(setupData.auctionParameters.auctionedToken);
    if (!auctionedToken) {
      throw new Error(`Auctioned token ${setupData.auctionParameters.auctionedToken} not found`);
    }

    const currencyAddress = await this.resolveCurrencyAddress(setupData.auctionParameters.currency);
    const { auctionParameters, env } = setupData;
    const startBlock = BigInt(env.startBlock) + BigInt(auctionParameters.startOffsetBlocks);
    const endBlock = startBlock + BigInt(auctionParameters.auctionDurationBlocks);
    const claimBlock = endBlock + BigInt(auctionParameters.claimDelayBlocks);
    
    const auctionAmount = this.calculateAuctionAmount(setupData.auctionParameters.auctionedToken, setupData.additionalTokens);
    
    console.log('   💰 Auction amount:', auctionAmount.toString());
    console.log('   💵 Currency address:', currencyAddress);
    console.log('   🪙 Auctioned token address:', await auctionedToken.getAddress());
    
    try {
      // Encode AuctionParameters struct
      const auctionParams = {
        currency: currencyAddress,
        tokensRecipient: auctionParameters.tokensRecipient,
        fundsRecipient: auctionParameters.fundsRecipient,
        startBlock: Number(startBlock),
        endBlock: Number(endBlock),
        claimBlock: Number(claimBlock),
        graduationThresholdMps: Number(auctionParameters.graduationThresholdMps),
        tickSpacing: Number(auctionParameters.tickSpacing),
        validationHook: auctionParameters.validationHook,
        floorPrice: auctionParameters.floorPrice,
        auctionStepsData: this.createSimpleAuctionStepsData(auctionParameters.auctionDurationBlocks)
      };

      const configData = this.ethers.AbiCoder.defaultAbiCoder().encode(
        [
          "tuple(address currency, address tokensRecipient, address fundsRecipient, uint64 startBlock, uint64 endBlock, uint64 claimBlock, uint24 graduationThresholdMps, uint256 tickSpacing, address validationHook, uint256 floorPrice, bytes auctionStepsData)"
        ],
        [auctionParams]
      );

      console.log('   📦 Config data length:', configData.length);

      const auctionAddress = await this.auctionFactory!.initializeDistribution.staticCall(
        await auctionedToken.getAddress(),
        auctionAmount,
        configData,
        this.ethers.keccak256(this.ethers.toUtf8Bytes("test-salt"))
      );
      
      // Now execute the actual transaction
      const tx = await this.auctionFactory!.initializeDistribution(
        await auctionedToken.getAddress(),
        auctionAmount,
        configData,
        this.ethers.keccak256(this.ethers.toUtf8Bytes("test-salt"))
      );
      await tx.wait();
      
      this.auction = await this.ethers.getContractAt('Auction', auctionAddress);
      return this.auction!;
    } catch (error: any) {
      console.error('   ❌ Auction creation failed:', error.message);
      throw error;
    }
  }

  async resolveCurrencyAddress(currency: string): Promise<string> {
    // If it's an address, return it directly
    if (currency.startsWith('0x')) {
      return currency;
    }
    // Special case for native currency (ETH, MATIC, BNB, etc.)
    if (currency === 'Native') {
      return '0x0000000000000000000000000000000000000000';
    }
    // Otherwise, look up the token by name
    const address = await this.getTokenAddress(currency);
    if (!address) {
      throw new Error(`Token ${currency} not found`);
    }
    return address;
  }

  calculateAuctionAmount(tokenName: string, additionalTokens: TokenConfig[]): bigint {
    const tokenConfig = additionalTokens.find(t => t.name === tokenName);
    if (!tokenConfig) {
      throw new Error(`Token ${tokenName} not found in additionalTokens`);
    }
    
    const totalSupply = BigInt(tokenConfig.totalSupply);
    const percentAuctioned = parseFloat(tokenConfig.percentAuctioned);
    return totalSupply * BigInt(Math.floor(percentAuctioned * 100)) / BigInt(10000);
  }

  createSimpleAuctionStepsData(auctionDurationBlocks: number): string {
    // Create a simple auction steps data that satisfies the validation
    // Format: each step is 8 bytes (uint64): 3 bytes mps + 5 bytes blockDelta
    // We need: sumMps = 1e7 (MPS constant) and sumBlockDelta = auctionDurationBlocks
    
    const MPS = 10000000; // 1e7
    const blockDelta = parseInt(auctionDurationBlocks.toString());
    const mps = Math.floor(MPS / blockDelta); // mps * blockDelta should equal MPS
    
    console.log('   🔍 Creating auction steps data:');
    console.log('   🔍   MPS:', MPS);
    console.log('   🔍   blockDelta:', blockDelta);
    console.log('   🔍   mps:', mps);
    
    // Pack mps (24 bits) and blockDelta (40 bits) into 8 bytes
    // mps goes in the upper 24 bits, blockDelta in the lower 40 bits
    const packed = (BigInt(mps) << 40n) | BigInt(blockDelta);
    
    // Convert to hex string with proper padding (8 bytes = 16 hex chars)
    const hex = packed.toString(16).padStart(16, '0');
    const result = '0x' + hex;
    
    console.log('   🔍   packed:', packed.toString());
    console.log('   🔍   hex:', result);
    
    return result;
  }

  async setupBalances(setupData: SetupData): Promise<void> {
    const { env } = setupData;
    if (!env.balances) return;

    console.log('   💰 Setting up balances...');

    for (const balance of env.balances) {
      if (balance.token === 'Native') {
        // Native currency balance - set native currency balance (ETH, MATIC, BNB, etc.)
        const hexAmount = '0x' + BigInt(balance.amount).toString(16);
        await this.hre.network.provider.send('hardhat_setBalance', [
          balance.address,
          hexAmount
        ]);
        console.log(`   ✅ Set native currency balance: ${balance.address} = ${balance.amount} wei`);
      } else if (balance.token.startsWith('0x')) {
        // It's an address - find the token by address
        let token: any = null;
        for (const [name, tokenContract] of this.tokens) {
          if (await tokenContract.getAddress() === balance.token) {
            token = tokenContract;
            break;
          }
        }
        
        if (token) {
          await token.mint(balance.address, balance.amount);
          console.log(`   ✅ Minted ${balance.amount} tokens to ${balance.address} (${await token.getAddress()})`);
        } else {
          console.warn(`   ⚠️  Token not found for address: ${balance.token}`);
        }
      } else {
        // It's a token name - look up by name
        const token = this.getTokenByName(balance.token);
        if (token) {
          await token.mint(balance.address, balance.amount);
          console.log(`   ✅ Minted ${balance.amount} ${balance.token} to ${balance.address}`);
        } else {
          console.warn(`   ⚠️  Token not found: ${balance.token}`);
        }
      }
    }
  }
}
